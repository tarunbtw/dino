//
//  AgentPlaybookRoutes.swift
//  nomad
//
//  Created by tarun on 15/10/26.
//

import Foundation
import Network

extension NomadAgentServer {
    func handlePlaybookRoute(method: String, cleanPath: String, bodyData: Data?, queryItem: (String) -> String?, connection: NWConnection, origin: String?) async -> Bool {
        let manager = AgentPlaybookManager.shared

        switch (method, cleanPath) {
        case ("POST", "/playbook/record"):
            var name = "playbook_\(Int(Date().timeIntervalSince1970))"
            if let bodyData = bodyData,
               let json = (try? JSONSerialization.jsonObject(with: bodyData)) as? [String: Any],
               let n = json["name"] as? String, !n.isEmpty {
                name = n
            } else if let qn = queryItem("name"), !qn.isEmpty {
                name = qn
            }
            manager.startRecording(name: name)
            sendJSON(connection: connection, object: [
                "success": true,
                "recording": true,
                "name": name,
                "message": "Playbook recording started"
            ], origin: origin)
            return true

        case ("POST", "/playbook/stop"):
            let actions = manager.stopRecording()
            let encodedActions = (try? JSONSerialization.jsonObject(with: JSONEncoder().encode(actions))) ?? []
            sendJSON(connection: connection, object: [
                "success": true,
                "recording": false,
                "name": manager.activeRecordingName,
                "actionCount": actions.count,
                "actions": encodedActions
            ], origin: origin)
            return true

        case ("POST", "/playbook/replay"):
            guard let activeTab = requireTab(id: queryItem("tabId"), connection: connection, origin: origin) else { return true }
            var actionsToReplay: [NomadAction]? = nil
            var variables: [String: String] = [:]

            if let bodyData = bodyData,
               let json = (try? JSONSerialization.jsonObject(with: bodyData)) as? [String: Any] {
                if let vars = json["variables"] as? [String: String] ?? json["params"] as? [String: String] {
                    variables = vars
                }
                if let actionsArr = json["actions"] as? [[String: Any]],
                   let actData = try? JSONSerialization.data(withJSONObject: actionsArr) {
                    actionsToReplay = try? JSONDecoder().decode([NomadAction].self, from: actData)
                } else if let name = json["name"] as? String {
                    actionsToReplay = manager.load(name: name)
                }
            } else if let name = queryItem("name") {
                actionsToReplay = manager.load(name: name)
            }

            guard let actions = actionsToReplay, !actions.isEmpty else {
                sendResponse(connection: connection, status: "400 Bad Request", body: "{\"error\":\"No actions or valid playbook name provided for replay\",\"code\":\"NO_ACTIONS\",\"success\":false}", origin: origin)
                return true
            }

            do {
                let replayResult = try await manager.replay(actions: actions, variables: variables, on: activeTab)
                sendJSON(connection: connection, object: [
                    "success": replayResult.success,
                    "executed": replayResult.executed,
                    "total": actions.count,
                    "error": replayResult.error as Any? ?? NSNull()
                ], origin: origin)
            } catch {
                sendResponse(connection: connection, status: "500 Internal Server Error", body: "{\"error\":\"\(error.localizedDescription)\",\"code\":\"REPLAY_ERROR\",\"success\":false}", origin: origin)
            }
            return true

        case ("GET", "/playbook/list"):
            manager.refreshSavedList()
            sendJSON(connection: connection, object: [
                "success": true,
                "isRecording": manager.isRecording,
                "activeRecording": manager.activeRecordingName,
                "playbooks": manager.savedPlaybookNames
            ], origin: origin)
            return true

        case ("GET", "/playbook/export"):
            guard let name = queryItem("name"), !name.isEmpty else {
                sendResponse(connection: connection, status: "400 Bad Request", body: "{\"error\":\"Missing required 'name' query parameter\",\"code\":\"MISSING_NAME\",\"success\":false}", origin: origin)
                return true
            }
            guard let actions = manager.load(name: name),
                  let data = try? JSONEncoder().encode(actions) else {
                sendResponse(connection: connection, status: "404 Not Found", body: "{\"error\":\"Playbook '\(name)' not found\",\"code\":\"NOT_FOUND\",\"success\":false}", origin: origin)
                return true
            }
            sendRaw(connection: connection, status: "200 OK", contentType: "application/json; charset=utf-8", data: data, origin: origin)
            return true

        case ("DELETE", "/playbook"):
            var name = queryItem("name")
            if name == nil, let bodyData = bodyData,
               let json = (try? JSONSerialization.jsonObject(with: bodyData)) as? [String: Any] {
                name = json["name"] as? String
            }
            guard let playbookName = name, !playbookName.isEmpty else {
                sendResponse(connection: connection, status: "400 Bad Request", body: "{\"error\":\"Missing required 'name'\",\"code\":\"MISSING_NAME\",\"success\":false}", origin: origin)
                return true
            }
            manager.delete(name: playbookName)
            sendJSON(connection: connection, object: [
                "success": true,
                "deleted": playbookName
            ], origin: origin)
            return true

        case ("GET", "/hitl/status"):
            guard let activeTab = requireTab(id: queryItem("tabId"), connection: connection, origin: origin) else { return true }
            let hitlStatus = await activeTab.checkHitlStatus()
            sendJSON(connection: connection, object: [
                "success": true,
                "isHitlActive": activeTab.isHitlActive,
                "challengeType": activeTab.hitlChallengeType as Any? ?? NSNull(),
                "detected": hitlStatus.detected,
                "type": hitlStatus.type as Any? ?? NSNull(),
                "resolved": hitlStatus.resolved
            ], origin: origin)
            return true

        case ("POST", "/hitl/resolve"):
            guard let activeTab = requireTab(id: queryItem("tabId"), connection: connection, origin: origin) else { return true }
            activeTab.isHitlActive = false
            activeTab.hitlChallengeType = nil
            sendJSON(connection: connection, object: [
                "success": true,
                "resolved": true,
                "message": "Human-in-the-loop challenge resolved and automation unblocked"
            ], origin: origin)
            return true

        default:
            return false
        }
    }
}

