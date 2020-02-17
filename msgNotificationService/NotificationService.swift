/*
* Copyright (c) 2010-2019 Belledonne Communications SARL.
*
* This file is part of linphone-iphone
*
* This program is free software: you can redistribute it and/or modify
* it under the terms of the GNU General Public License as published by
* the Free Software Foundation, either version 3 of the License, or
* (at your option) any later version.
*
* This program is distributed in the hope that it will be useful,
* but WITHOUT ANY WARRANTY; without even the implied warranty of
* MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
* GNU General Public License for more details.
*
* You should have received a copy of the GNU General Public License
* along with this program. If not, see <http://www.gnu.org/licenses/>.
*/

import UserNotifications
import linphonesw

var GROUP_ID = "group.org.linphone.phone.msgNotification"

struct MsgData: Codable {
    var from: String?
    var body: String?
    var subtitle: String?
    var callId: String?
    var localAddr: String?
    var peerAddr: String?
}

class NotificationService: UNNotificationServiceExtension { // TODO PAUL : add logs

    var contentHandler: ((UNNotificationContent) -> Void)?
    var bestAttemptContent: UNMutableNotificationContent?

    var lc: Core?
    static var logDelegate: LinphoneLoggingServiceManager!
	static var log: LoggingService!

    override func didReceive(_ request: UNNotificationRequest, withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void) {
        self.contentHandler = contentHandler
        bestAttemptContent = (request.content.mutableCopy() as? UNMutableNotificationContent)
        NSLog("[msgNotificationService] start msgNotificationService extension")

		if let bestAttemptContent = bestAttemptContent {
			createCore()

			if let isChatRoomInvite = bestAttemptContent.userInfo["chat-room-invite"] as? Int, isChatRoomInvite == 1 {
				NotificationService.log.message(msg: "[msgNotificationService] fetch chat room for invite")
				let chatRoom = lc!.pushNotificationChatRoomInvite
				stopCore()
				if let chatRoom = chatRoom {
					NotificationService.log.message(msg: "[msgNotificationService] chat room invite received")
					bestAttemptContent.title = "You have been added to a chat room" // TODO PAUL : differencier single lime cr / group chat ?
//					bestAttemptContent.body = chatRoom.subject // TODO PAUL : don't display the good one

					contentHandler(bestAttemptContent)
					return
				}
			} else if let callId = bestAttemptContent.userInfo["call-id"] as? String {
				NotificationService.log.message(msg: "[msgNotificationService] fetch msg")
				let message = lc!.getPushNotificationMessage(callId: callId)

				if let message = message, let chatRoom = message.chatRoom {
					let msgData = parseMessage(room: chatRoom, message: message)

					if let badge = updateBadge() as NSNumber? {
						bestAttemptContent.badge = badge
					}

					stopCore()

					bestAttemptContent.sound = UNNotificationSound(named: UNNotificationSoundName(rawValue: "msg.caf"))
					bestAttemptContent.title = NSLocalizedString("Message received", comment: "") + " [extension]"
					if let subtitle = msgData?.subtitle {
						bestAttemptContent.subtitle = subtitle
					}
					if let body = msgData?.body {
						bestAttemptContent.body = body
					}

					bestAttemptContent.categoryIdentifier = "msg_cat"

					bestAttemptContent.userInfo.updateValue(msgData?.callId as Any, forKey: "CallId")
					bestAttemptContent.userInfo.updateValue(msgData?.from as Any, forKey: "from")
					bestAttemptContent.userInfo.updateValue(msgData?.peerAddr as Any, forKey: "peer_addr")
					bestAttemptContent.userInfo.updateValue(msgData?.localAddr as Any, forKey: "local_addr")

					contentHandler(bestAttemptContent)
					return
				}
			}
			serviceExtensionTimeWillExpire()
        }
    }

    override func serviceExtensionTimeWillExpire() {
        // Called just before the extension will be terminated by the system.
        // Use this as an opportunity to deliver your "best attempt" at modified content, otherwise the original push payload will be used.
		stopCore()
        if let contentHandler = contentHandler, let bestAttemptContent =  bestAttemptContent {
            NSLog("[msgNotificationService] serviceExtensionTimeWillExpire")
            bestAttemptContent.categoryIdentifier = "app_active"
            bestAttemptContent.title = NSLocalizedString("Message received", comment: "") + " [time out]" // TODO PAUL : a enlever
            bestAttemptContent.body = NSLocalizedString("You have received a message.", comment: "")          
            contentHandler(bestAttemptContent)
        }
    }

	func parseMessage(room: ChatRoom, message: ChatMessage) -> MsgData? {
		NotificationService.log.message(msg: "[msgNotificationService] Core received msg \(message.contentType) \n")

		if (message.contentType != "text/plain" && message.contentType != "image/jpeg") {
			return nil
		}

		let content = message.isText ? message.textContent : "🗻"
		let from = message.fromAddress?.username
		let callId = message.getCustomHeader(headerName: "Call-Id")
		let localUri = room.localAddress?.asStringUriOnly()
		let peerUri = room.peerAddress?.asStringUriOnly()

		var msgData = MsgData(from: from, body: "", subtitle: "", callId:callId, localAddr: localUri, peerAddr:peerUri)

		if let showMsg = lc!.config?.getBool(section: "app", key: "show_msg_in_notif", defaultValue: true), showMsg == true {
			if let subject = room.subject as String?, subject != "" {
				msgData.subtitle = subject
				msgData.body = from! + " : " + content
			} else {
				msgData.subtitle = from
				msgData.body = content
			}
		} else {
			if let subject = room.subject as String?, subject != "" {
				msgData.body = subject + " : " + from!
			} else {
				msgData.body = from
			}
		}

		NotificationService.log.message(msg: "[msgNotificationService] msg: \(content) \n")
		return msgData;
	}

	func setCoreLogger(config: Config) {
		if (NotificationService.log == nil || NotificationService.log.getDelegate() == nil) {
			let debugLevel = config.getInt(section: "app", key: "debugenable_preference", defaultValue: LogLevel.Debug.rawValue)
			let debugEnabled = (debugLevel >= LogLevel.Debug.rawValue && debugLevel < LogLevel.Error.rawValue)

			if (debugEnabled) {
				NotificationService.log = LoggingService.Instance /*enable liblinphone logs.*/
				NotificationService.logDelegate = LinphoneLoggingServiceManager()
				NotificationService.log.domain = "msgNotificationService"
				NotificationService.log.logLevel = LogLevel(rawValue: debugLevel)
				NotificationService.log.addDelegate(delegate: NotificationService.logDelegate)
			}
		}
	}
	
	func createCore() {
		NSLog("[msgNotificationService] create core")
		let config = Config.newForSharedCore(groupId: GROUP_ID, configFilename: "linphonerc", factoryPath: "")
		setCoreLogger(config: config!)
		lc = try! Factory.Instance.createSharedCoreWithConfig(config: config!, systemContext: nil, appGroup: GROUP_ID, mainCore: false)
	}

	func stopCore() {
		NotificationService.log.message(msg: "[msgNotificationService] stop core")
		if let lc = lc {
			lc.stop()
		}
	}

    func updateBadge() -> Int {
        var count = 0
        count += lc!.unreadChatMessageCount
        count += lc!.missedCallsCount
        count += lc!.callsNb
		NotificationService.log.message(msg: "[msgNotificationService] badge: \(count)\n")

        return count
    }
}
