//
//  NotificationViewController.swift
//  msgNotificationContent
//
//  Created by Paul Cartier on 10/12/2019.
//

import UIKit
import UserNotifications
import UserNotificationsUI
import linphonesw


var GROUP_ID = "group.org.linphone.phone.msgNotification"
var isRegistered: Bool = false
var isReplySent: Bool = false
var needToStop: Bool = false

class NotificationViewController: UIViewController, UNNotificationContentExtension {

    @IBOutlet var label: UILabel?
    var lc: Core?
    
//    override func viewWillDisappear(_ animated: Bool) {
//        super.viewWillDisappear(animated)
//        lc?.stop() // TODO PAUL : garder ca si il y a un call pour supprimer le core?
//    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any required interface initialization here.
        
        let replyAction = UNTextInputNotificationAction(identifier: "Reply",
                         title: "Reply",
                         options: [],
                         textInputButtonTitle: "Send",
                         textInputPlaceholder: "")
        
        let seenAction = UNNotificationAction(identifier: "Seen", title: "Mark as seen", options: [])
        let category = UNNotificationCategory(identifier: "msg_cat", actions: [replyAction, seenAction], intentIdentifiers: [], options: [.customDismissAction])
        UNUserNotificationCenter.current().setNotificationCategories([category])
        

        
        isRegistered = false
        needToStop = false
        isReplySent = false
        
        // TODO PAUL handle dismiss action : already done?
    }
    
    func didReceive(_ notification: UNNotification) {
//        self.label?.text = notification.request.content.body // title
        self.label?.text = "test test test"
    }
    
    func didReceive(_ response: UNNotificationResponse,
                    completionHandler completion: @escaping (UNNotificationContentExtensionResponseOption) -> Void) {
        let userInfo = response.notification.request.content.userInfo
        switch response.actionIdentifier {
        case "Reply":
            if let replyText = response as? UNTextInputNotificationResponse {
                replyAction(userInfo, text: replyText.userText, completionHandler: completion)
            }
            break
        case "Seen":
            markAsSeenAction(userInfo, completionHandler: completion)
            break
        default:
            break
        }
        
//        completion(.dismiss) // TODO PAUL : ok mais dans le cas on ouvre la notif : .dissmisAndForward -> open app conv -> deja fait?
    }
    
    func markAsSeenAction(_ userInfo: [AnyHashable : Any], completionHandler completion: @escaping (UNNotificationContentExtensionResponseOption) -> Void) {
        NSLog("[EXTENSION] markAsSeenAction")
        do {
            try startCore(completionHandler: completion)
            
            let peerAddress = userInfo["peer_addr"] as! String
            let localAddress = userInfo["local_addr"] as! String
            let peer = try! lc!.createAddress(address: peerAddress)
            let local = try! lc!.createAddress(address: localAddress)
            let room = lc!.findChatRoom(peerAddr: peer, localAddr: local)
            if let room = room {
    //            let roomDelegate = LinphoneChatRoomManager()
    //            room.addDelegate(delegate: roomDelegate)
                room.markAsRead()
            }
            
//            lc!.iterate() // TODO PAUL : needed?
        } catch {
            NSLog("[EXTENSION] error: \(error)")
            completion(.dismissAndForwardAction)
        }
        lc!.networkReachable = false
        lc!.stop()
    }
    
    func replyAction(_ userInfo: [AnyHashable : Any], text replyText: String, completionHandler completion: @escaping (UNNotificationContentExtensionResponseOption) -> Void) {
        NSLog("[EXTENSION] replyAction")
        do {
            try startCore(completionHandler: completion)
            
            let peerAddress = userInfo["peer_addr"] as! String
            let localAddress = userInfo["local_addr"] as! String
            let peer = try! lc!.createAddress(address: peerAddress)
            let local = try! lc!.createAddress(address: localAddress)
            let room = lc!.findChatRoom(peerAddr: peer, localAddr: local)
            if let room = room {
                let msgDelegate = LinphoneChatMessageManager()
                let chatMsg = try! room.createMessage(message: replyText)
                chatMsg.addDelegate(delegate: msgDelegate)
                room.sendChatMessage(msg: chatMsg)
                room.markAsRead()
            }
            
            var i = 0
            while(!isReplySent && !needToStop) {
                lc!.iterate()
                NSLog("[EXTENSION] \(i)")
                i += 1;
                usleep(100000)
            }
        } catch {
            NSLog("[EXTENSION] error: \(error)")
            completion(.dismissAndForwardAction)
        }
        lc!.networkReachable = false
        lc!.stop()
    }
    
    func startCore(completionHandler completion: @escaping (UNNotificationContentExtensionResponseOption) -> Void) throws {
        let log = LoggingService.Instance /*enable liblinphone logs.*/
        let logManager = LinphoneLoggingServiceManager()
        log.logLevel = LogLevel.Message
        log.addDelegate(delegate: logManager)
    
        lc = try! Factory.Instance.createSharedCore(configPath: FileManager.preferenceFile(file: "linphonerc").path, factoryConfigPath: "", systemContext: nil, appGroup: GROUP_ID, mainCore: false)
        
        let coreManager = LinphoneCoreManager(self)
        lc!.addDelegate(delegate: coreManager)
        
        try lc!.start()
        completion(.dismiss)
        
        NSLog("[EXTENSION] core started")
        lc!.refreshRegisters()
        
        var i = 0
        while(!isRegistered && !needToStop) {
            lc!.iterate()
            NSLog("[EXTENSION] \(i)")
            i += 1;
            usleep(100000)
        }
    }
    
    class LinphoneCoreManager: CoreDelegate {
        unowned let parent: NotificationViewController
        
        init(_ parent: NotificationViewController) {
            self.parent = parent
        }
        
        override func onGlobalStateChanged(lc: Core, gstate: GlobalState, message: String) {
            NSLog("[EXTENSION] onGlobalStateChanged \(gstate) : \(message) \n")
            if (gstate == .Shutdown) {
                //                parent.serviceExtensionTimeWillExpire() // TODO PAUL : dismiss a gérer pour renvoyer a l'appli (on aura déja fait dismis, pas evident
//                completion(.dismissAndForwardAction)??
                needToStop = true
            }
        }
        
        override func onRegistrationStateChanged(lc: Core, cfg: ProxyConfig, cstate: RegistrationState, message: String?) {
            NSLog("[EXTENSION] New registration state \(cstate) for user id \( String(describing: cfg.identityAddress?.asString()))\n")
            if (cstate == .Ok) {
                isRegistered = true
            }
        }
    }
    
//    class LinphoneChatRoomManager: ChatRoomDelegate {
//        override func onImdnDelivered(cr: ChatRoom) {
//            NSLog("[EXTENSION] onImdnDelivered \n")
//            isImdnDelivered = true
//        }
//    }

    class LinphoneChatMessageManager: ChatMessageDelegate {
        override func onMsgStateChanged(msg: ChatMessage, state: ChatMessage.State) {
            NSLog("[EXTENSION] onMsgStateChanged: \(state)\n")
            if (state == .InProgress) {
                isReplySent = true
            }
        }
    }
}

class LinphoneLoggingServiceManager: LoggingServiceDelegate {
    override func onLogMessageWritten(logService: LoggingService, domain: String, lev: LogLevel, message: String) {
        let level: String
        
        switch lev {
        case .Debug:
            level = "Debug"
        case .Trace:
            level = "Trace"
        case .Message:
            level = "Message"
        case .Warning:
            level = "Warning"
        case .Error:
            level = "Error"
        case .Fatal:
            level = "Fatal"
        default:
            level = "unknown"
        }
        
        NSLog("[SDK] \(level): \(message)\n")
    }
}

extension FileManager {
    static func sharedContainerURL() -> URL {
        return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: GROUP_ID)!
    }
    
    static func exploreSharedContainer() {
        if let content = try? FileManager.default.contentsOfDirectory(atPath: FileManager.sharedContainerURL().path) {
            content.forEach { file in
                NSLog(file)
            }
        }
    }
    
    static func preferenceFile(file: String) -> URL {
        let fullPath = FileManager.sharedContainerURL().appendingPathComponent("Library/Preferences/linphone/")
        return fullPath.appendingPathComponent(file)
    }
    
    static func dataFile(file: String) -> URL {
        let fullPath = FileManager.sharedContainerURL().appendingPathComponent("Library/Application Support/linphone/")
        return fullPath.appendingPathComponent(file)
    }
}
