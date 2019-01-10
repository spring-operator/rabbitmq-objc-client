// This source code is dual-licensed under the Mozilla Public License ("MPL"),
// version 1.1 and the Apache License ("ASL"), version 2.0.
//
// The ASL v2.0:
//
// ---------------------------------------------------------------------------
// Copyright 2017-2019 Pivotal Software, Inc.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//    http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
// ---------------------------------------------------------------------------
//
// The MPL v1.1:
//
// ---------------------------------------------------------------------------
// The contents of this file are subject to the Mozilla Public License
// Version 1.1 (the "License"); you may not use this file except in
// compliance with the License. You may obtain a copy of the License at
// https://www.mozilla.org/MPL/
//
// Software distributed under the License is distributed on an "AS IS"
// basis, WITHOUT WARRANTY OF ANY KIND, either express or implied. See the
// License for the specific language governing rights and limitations
// under the License.
//
// The Original Code is RabbitMQ
//
// The Initial Developer of the Original Code is Pivotal Software, Inc.
// All Rights Reserved.
//
// Alternatively, the contents of this file may be used under the terms
// of the Apache Standard license (the "ASL License"), in which case the
// provisions of the ASL License are applicable instead of those
// above. If you wish to allow use of your version of this file only
// under the terms of the ASL License and not to allow others to use
// your version of this file under the MPL, indicate your decision by
// deleting the provisions above and replace them with the notice and
// other provisions required by the ASL License. If you do not delete
// the provisions above, a recipient may use your version of this file
// under either the MPL or the ASL License.
// ---------------------------------------------------------------------------

import XCTest

// see https://github.com/rabbitmq/rabbitmq-objc-client/blob/master/CONTRIBUTING.md
// to set up your system for running integration tests
class QueueIntegrationTest: XCTestCase {
    func testQueueAndConsumerDSLAutomaticAcknowledgementMode() {
        _ = IntegrationHelper.withChannel { ch in
            let x = ch.fanout("objc.tests.fanouts.testQueueAndConsumerDSLAutomaticAcknowledgementMode", options: [])

            let cons = ch.queue("", options: [.exclusive])
                .bind(x)
                .subscribe([.automaticAckMode]) { _ in
                    // no-op
            }
            XCTAssertTrue(cons.usesAutomaticAckMode())
            XCTAssertFalse(cons.usesManualAckMode())

            x.delete()
        }
    }

    func testQueueAndConsumerDSLManualAcknowledgementMode() {
        _ = IntegrationHelper.withChannel { ch in
            let x = ch.fanout("objc.tests.fanouts.testQueueAndConsumerDSLManualAcknowledgementMode", options: [])

            let cons = ch.queue("", options: [.exclusive])
                .bind(x)
                .subscribe([.manualAckMode]) { _ in
                    // no-op
            }
            XCTAssertFalse(cons.usesAutomaticAckMode())
            XCTAssertTrue(cons.usesManualAckMode())

            x.delete()
        }
    }

    func testQueueAndConsumerDSLExclusiveConsumerWithAutomaticAcknowledgementMode() {
        _ = IntegrationHelper.withChannel { ch in
            let x = ch.fanout("objc.tests.fanouts.testQueueAndConsumerDSLExclusiveConsumer", options: [])

            let cons = ch.queue("", options: [.exclusive])
                .bind(x)
                .subscribe([.automaticAckMode, .exclusive]) { _ in
                    // no-op
            }
            XCTAssertTrue(cons.usesAutomaticAckMode())
            XCTAssertTrue(cons.isExclusive())

            x.delete()
        }
    }

    func testManualAcknowledgementOfASingleDelivery() {
        _ = IntegrationHelper.withChannel { ch in
            let x = ch.fanout("objc.tests.fanouts.testManualAcknowledgementOfASingleDelivery", options: [])

            let semaphore = DispatchSemaphore(value: 0)
            var delivered: RMQMessage?

            let cons = ch.queue("", options: [.exclusive])
                .bind(x)
                .subscribe([.manualAckMode]) { message in
                    delivered = message
                    ch.ack(message.deliveryTag)
                    semaphore.signal()
            }

            let body = "msg".data(using: String.Encoding.utf8)!
            x.publish(body)

            XCTAssertEqual(.success,
                           semaphore.wait(timeout: TestHelper.dispatchTimeFromNow(5)),
                           "Timed out waiting for a delivery")
            XCTAssertEqual(body, delivered!.body)
            XCTAssertEqual(delivered!.consumerTag, cons.tag)
            XCTAssertEqual(delivered!.deliveryTag, 1)
            XCTAssertFalse(delivered!.isRedelivered)

            x.delete()
        }
    }

    func testManualAcknowledgementOfMultipleDeliveries() {
        _ = IntegrationHelper.withChannel { ch in
            let x = ch.fanout("objc.tests.fanouts.testManualAcknowledgementOfMultipleDeliveries", options: [])

            let semaphore = DispatchSemaphore(value: 0)
            let total = 100
            let counter = AtomicInteger(value: 0)

            ch.queue("", options: [.exclusive])
                .bind(x)
                .subscribe([.manualAckMode]) { message in
                    if counter.value >= total {
                        ch.ack(message.deliveryTag, options: [.multiple])
                        semaphore.signal()
                    } else {
                        _ = counter.incrementAndGet()
                    }
            }

            let body = "msg".data(using: String.Encoding.utf8)!
            for _ in (0...total) {
                x.publish(body)
            }

            XCTAssertEqual(.success,
                           semaphore.wait(timeout: TestHelper.dispatchTimeFromNow(5)),
                           "Timed out waiting for acks")

            x.delete()
        }
    }

    func testNegativeAcknowledgementOfMultipleDeliveries() {
        _ = IntegrationHelper.withChannel { ch in
            let semaphore = DispatchSemaphore(value: 0)
            let total = 100
            let counter = AtomicInteger(value: 0)

            let q = ch.queue("", options: [.exclusive])
            q.subscribe([.manualAckMode]) { message in
                    if counter.value >= total {
                        ch.nack(message.deliveryTag, options: [.multiple])
                        semaphore.signal()
                    } else {
                        _ = counter.incrementAndGet()
                    }
            }

            let body = "msg".data(using: String.Encoding.utf8)!
            for _ in (0...total) {
                ch.defaultExchange().publish(body, routingKey: q.name!)
            }

            XCTAssertEqual(.success,
                           semaphore.wait(timeout: TestHelper.dispatchTimeFromNow(5)),
                           "Timed out waiting for acks")
        }
    }

    func testNegativeAcknowledgementWithRequeueingRedelivers() {
        _ = IntegrationHelper.withChannel { ch in
            let q = ch.queue("", options: [.autoDelete, .exclusive])
            let semaphore = DispatchSemaphore(value: 0)

            var isRejected = false
            q.subscribe([.manualAckMode]) { message in
                if isRejected {
                    semaphore.signal()
                } else {
                    ch.reject(message.deliveryTag, options: [.requeue])
                    isRejected = true
                }
            }

            ch.defaultExchange().publish("msg".data(using: String.Encoding.utf8), routingKey: q.name)

            XCTAssertEqual(.success,
                           semaphore.wait(timeout: TestHelper.dispatchTimeFromNow(10)),
                           "Timed out waiting for a redelivery")
        }
    }

    func testNegativeAcknowledgementWithRequeueingRedeliversToADifferentConsumer() {
        _ = IntegrationHelper.withChannel { ch in
            let q = ch.queue("", options: [.autoDelete, .exclusive])
            let semaphore = DispatchSemaphore(value: 0)
            let counter = AtomicInteger(value: 0)
            var activeTags: [String] = []
            var delivered: RMQMessage?

            let handler: RMQConsumerDeliveryHandler = { (message: RMQMessage) -> Void in
                if counter.value < 10 {
                    activeTags.append(message.consumerTag)
                    ch.nack(message.deliveryTag, options: [.requeue])
                    _ = counter.incrementAndGet()
                } else {
                    delivered = message
                    semaphore.signal()
                }
            }

            // 3 competing consumers
            let cons1 = q.subscribe([.manualAckMode], handler: handler)
            let cons2 = q.subscribe([.manualAckMode], handler: handler)
            let cons3 = q.subscribe([.manualAckMode], handler: handler)

            ch.defaultExchange().publish("msg".data(using: String.Encoding.utf8), routingKey: q.name)

            XCTAssertEqual(.success,
                           semaphore.wait(timeout: TestHelper.dispatchTimeFromNow(10)),
                           "Timed out waiting for N redeliveries")
            XCTAssertTrue(activeTags.contains(cons1.tag))
            XCTAssertTrue(activeTags.contains(cons2.tag))
            XCTAssertTrue(activeTags.contains(cons3.tag))
            XCTAssertTrue(delivered!.isRedelivered)
        }
    }
}
