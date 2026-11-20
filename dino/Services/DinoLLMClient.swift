//
//  DinoLLMClient.swift
//  dino
//
//  Created for Dino Browser.
//  Lightweight, unified LLM client using pure Swift URLSession.
//  Zero dependencies. Supports Gemini, Claude, OpenAI, and Local Ollama with tool calling.
//

import Foundation

struct AgentToolCall: Equatable {
    let name: String
    let arguments: [String: Any]

    static func == (lhs: AgentToolCall, rhs: AgentToolCall) -> Bool {
        lhs.name == rhs.name && (lhs.arguments as NSDictionary).isEqual(to: rhs.arguments)
    }
}

struct AgentStepResponse {
    let thought: String
    let toolCall: AgentToolCall?
}

enum DinoLLMError: LocalizedError {
    case missingAPIKey(String)
    case invalidResponse(String)
    case networkError(String)
    case unsupportedProvider(String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey(let provider): return "Missing API key for \(provider). Please set it in Autopilot settings."
        case .invalidResponse(let msg): return "LLM response error: \(msg)"
        case .networkError(let msg): return "Network connection error: \(msg)"
        case .unsupportedProvider(let p): return "Unsupported model provider: \(p)"
        }
    }
}

final class DinoLLMClient {
    static let shared = DinoLLMClient()
    private let session = URLSession(configuration: .default)

    private init() {}

    // Tool declarations schema
    static let browserTools: [[String: Any]] = [
        [
            "name": "click",
            "description": "Click an interactable element on the page using its reference ID (e.g. 'c1', 'btn-submit').",
            "parameters": [
                "type": "object",
                "properties": [
                    "ref": ["type": "string", "description": "The reference ID of the element to click."],
                    "reason": ["type": "string", "description": "Short explanation of why clicking this element."]
                ],
                "required": ["ref"]
            ]
        ],
        [
            "name": "type",
            "description": "Type text into an input field or search bar identified by its ref ID.",
            "parameters": [
                "type": "object",
                "properties": [
                    "ref": ["type": "string", "description": "The reference ID of the input field (e.g. 'e4'). Do not include brackets."],
                    "text": ["type": "string", "description": "The text to type into the field."],
                    "pressEnter": ["type": "boolean", "description": "Whether to press Enter after typing to submit. ALWAYS set to true for search bars."]
                ],
                "required": ["ref", "text"]
            ]
        ],
        [
            "name": "scroll",
            "description": "Scroll the page viewport up or down to reveal more content. NOTE: Use only for long text articles, tables, or feeds. Do NOT use scroll repeatedly on dashboards/portals to find navigation sections; use click on the navigation menu or sidebar instead.",
            "parameters": [
                "type": "object",
                "properties": [
                    "direction": ["type": "string", "enum": ["up", "down"], "description": "Scroll direction."],
                    "amount": ["type": "integer", "description": "Scroll amount in pixels (default 400)."]
                ],
                "required": ["direction"]
            ]
        ],
        [
            "name": "navigate",
            "description": "Navigate the browser to a specific URL.",
            "parameters": [
                "type": "object",
                "properties": [
                    "url": ["type": "string", "description": "The destination URL."]
                ],
                "required": ["url"]
            ]
        ],
        [
            "name": "ask_user",
            "description": "Pause execution and ask the human user a question or request manual input (e.g. OTP, 2FA, password, clarification).",
            "parameters": [
                "type": "object",
                "properties": [
                    "question": ["type": "string", "description": "The question or instruction for the human user."]
                ],
                "required": ["question"]
            ]
        ],
        [
            "name": "complete",
            "description": "Mark the task as completed and provide a summary of what was accomplished.",
            "parameters": [
                "type": "object",
                "properties": [
                    "summary": ["type": "string", "description": "Final summary of task results for the user."]
                ],
                "required": ["summary"]
            ]
        ]
    ]

    /// Requests the next reasoning step from the configured model provider.
    func nextStep(
        goal: String,
        history: [[String: Any]],
        currentDOM: String,
        activeURL: URL?,
        pageTitle: String
    ) async throws -> AgentStepResponse {
        let vault = DinoModelVault.shared
        let provider = vault.activeProvider
        let model = vault.selectedModel

        switch provider {
        case .gemini:
            guard let key = vault.key(for: .gemini) else {
                throw DinoLLMError.missingAPIKey("Google Gemini")
            }
            return try await callGemini(key: key, model: model, goal: goal, history: history, currentDOM: currentDOM, activeURL: activeURL, pageTitle: pageTitle)

        case .claude:
            guard let key = vault.key(for: .claude) else {
                throw DinoLLMError.missingAPIKey("Anthropic Claude")
            }
            return try await callClaude(key: key, model: model, goal: goal, history: history, currentDOM: currentDOM, activeURL: activeURL, pageTitle: pageTitle)

        case .openrouter, .openai, .ollama:
            let apiKey = vault.key(for: provider) ?? (provider == .ollama ? "ollama" : "")
            if provider != .ollama && apiKey.isEmpty {
                throw DinoLLMError.missingAPIKey(provider.displayName)
            }
            var targetModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
            if provider == .openrouter {
                // Auto-correct numeral 1 typo in vision-language models (e.g. super-v1:free -> super-vl:free)
                if targetModel.contains("super-v1") {
                    targetModel = targetModel.replacingOccurrences(of: "super-v1", with: "super-vl")
                }
                // Fallback for sunsetted claude-3.5-sonnet on OpenRouter
                if targetModel == "anthropic/claude-3.5-sonnet" {
                    targetModel = "nvidia/nemotron-3.5-super-vl:free"
                }
            }
            let endpoint: String
            switch provider {
            case .openrouter:
                endpoint = "https://openrouter.ai/api/v1/chat/completions"
            case .ollama:
                endpoint = "\(vault.ollamaEndpoint)/chat/completions"
            case .openai:
                endpoint = "https://api.openai.com/v1/chat/completions"
            default:
                endpoint = "https://openrouter.ai/api/v1/chat/completions"
            }
            return try await callOpenAICompatible(endpoint: endpoint, apiKey: apiKey, model: targetModel, goal: goal, history: history, currentDOM: currentDOM, activeURL: activeURL, pageTitle: pageTitle)
        }
    }

    // MARK: - Gemini Implementation

    private func callGemini(key: String, model: String, goal: String, history: [[String: Any]], currentDOM: String, activeURL: URL?, pageTitle: String) async throws -> AgentStepResponse {
        let cleanModel = model.hasPrefix("models/") ? String(model.dropFirst(7)) : model
        let targetModel = (cleanModel.isEmpty || cleanModel == "gemini-1.5-pro") ? "gemini-2.5-flash" : cleanModel
        let endpoint = "https://generativelanguage.googleapis.com/v1beta/models/\(targetModel):generateContent?key=\(key)"
        guard let url = URL(string: endpoint) else { throw DinoLLMError.networkError("Invalid Gemini endpoint") }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let framedDOM = DinoDOMSanitizer.frameUntrustedContent(domTree: currentDOM, url: activeURL, title: pageTitle)
        let systemPrompt = DinoAgentHarness.systemPrompt

        var contents: [[String: Any]] = []
        var mergedTurns: [(role: String, text: String)] = []

        if history.isEmpty {
            mergedTurns.append(("user", "User Goal:\n\(goal)\n\nCurrent Page State:\n\(framedDOM)"))
        } else {
            mergedTurns.append(("user", "User Goal:\n\(goal)"))
            for item in history.suffix(6) {
                let role = (item["role"] as? String) == "assistant" ? "model" : "user"
                let text = (item["text"] as? String) ?? ""
                if !text.isEmpty {
                    mergedTurns.append((role, text))
                }
            }
            mergedTurns.append(("user", "Current Page State:\n\(framedDOM)\n\nProvide the next action or complete."))
        }

        // Strictly enforce Gemini's alternating user/model requirement by merging consecutive turns
        for turn in mergedTurns {
            if let last = contents.last, (last["role"] as? String) == turn.role {
                var updated = last
                var parts = (updated["parts"] as? [[String: Any]]) ?? []
                parts.append(["text": turn.text])
                updated["parts"] = parts
                contents[contents.count - 1] = updated
            } else {
                contents.append([
                    "role": turn.role,
                    "parts": [["text": turn.text]]
                ])
            }
        }

        let geminiTools: [[String: Any]] = [
            [
                "functionDeclarations": Self.browserTools.map { tool in
                    [
                        "name": tool["name"] as? String ?? "",
                        "description": tool["description"] as? String ?? "",
                        "parameters": tool["parameters"] as? [String: Any] ?? [:]
                    ]
                }
            ]
        ]

        let payload: [String: Any] = [
            "system_instruction": [
                "parts": [
                    ["text": systemPrompt]
                ]
            ],
            "contents": contents,
            "tools": geminiTools,
            "generationConfig": [
                "temperature": 0.2
            ]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            var errorMsg = "HTTP \( (response as? HTTPURLResponse)?.statusCode ?? 500)"
            if let errJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let errObj = errJson["error"] as? [String: Any],
               let m = errObj["message"] as? String {
                errorMsg = m
            } else if let raw = String(data: data, encoding: .utf8), !raw.isEmpty {
                errorMsg = raw
            }
            throw DinoLLMError.invalidResponse(errorMsg)
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = json["candidates"] as? [[String: Any]],
              let first = candidates.first,
              let content = first["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]] else {
            throw DinoLLMError.invalidResponse("Malformed Gemini JSON response")
        }

        var thought = ""
        var toolCall: AgentToolCall? = nil

        for part in parts {
            if let t = part["text"] as? String {
                thought += t
            }
            if let call = part["functionCall"] as? [String: Any],
               let name = call["name"] as? String {
                let args = (call["args"] as? [String: Any]) ?? [:]
                toolCall = AgentToolCall(name: name, arguments: args)
            }
        }

        return AgentStepResponse(thought: thought.trimmingCharacters(in: .whitespacesAndNewlines), toolCall: toolCall)
    }

    // MARK: - Claude Implementation

    private func callClaude(key: String, model: String, goal: String, history: [[String: Any]], currentDOM: String, activeURL: URL?, pageTitle: String) async throws -> AgentStepResponse {
        let endpoint = "https://api.anthropic.com/v1/messages"
        guard let url = URL(string: endpoint) else { throw DinoLLMError.networkError("Invalid Claude endpoint") }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(key, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        let framedDOM = DinoDOMSanitizer.frameUntrustedContent(domTree: currentDOM, url: activeURL, title: pageTitle)
        let systemPrompt = DinoAgentHarness.systemPrompt

        var messages: [[String: Any]] = []
        messages.append([
            "role": "user",
            "content": "User Goal: \(goal)\n\nCurrent Page State:\n\(framedDOM)"
        ])

        for item in history.suffix(6) {
            if let role = item["role"] as? String, let text = item["text"] as? String {
                messages.append(["role": role, "content": text])
            }
        }

        let claudeTools = Self.browserTools.map { tool -> [String: Any] in
            [
                "name": tool["name"] as? String ?? "",
                "description": tool["description"] as? String ?? "",
                "input_schema": tool["parameters"] as? [String: Any] ?? [:]
            ]
        }

        let payload: [String: Any] = [
            "model": model,
            "max_tokens": 1024,
            "system": systemPrompt,
            "messages": messages,
            "tools": claudeTools,
            "temperature": 0.2
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let msg = String(data: data, encoding: .utf8) ?? "HTTP \( (response as? HTTPURLResponse)?.statusCode ?? 500)"
            throw DinoLLMError.invalidResponse(msg)
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let contents = json["content"] as? [[String: Any]] else {
            throw DinoLLMError.invalidResponse("Malformed Claude response")
        }

        var thought = ""
        var toolCall: AgentToolCall? = nil

        for item in contents {
            if let type = item["type"] as? String {
                if type == "text", let text = item["text"] as? String {
                    thought += text
                } else if type == "tool_use", let name = item["name"] as? String {
                    let input = (item["input"] as? [String: Any]) ?? [:]
                    toolCall = AgentToolCall(name: name, arguments: input)
                }
            }
        }

        return AgentStepResponse(thought: thought.trimmingCharacters(in: .whitespacesAndNewlines), toolCall: toolCall)
    }

    // MARK: - OpenAI / Ollama Implementation

    private func callOpenAICompatible(endpoint: String, apiKey: String, model: String, goal: String, history: [[String: Any]], currentDOM: String, activeURL: URL?, pageTitle: String) async throws -> AgentStepResponse {
        guard let url = URL(string: endpoint) else { throw DinoLLMError.networkError("Invalid endpoint URL: \(endpoint)") }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        if endpoint.contains("openrouter.ai") {
            request.setValue("https://dino.browser", forHTTPHeaderField: "HTTP-Referer")
            request.setValue("Dino Browser", forHTTPHeaderField: "X-Title")
        }

        let framedDOM = DinoDOMSanitizer.frameUntrustedContent(domTree: currentDOM, url: activeURL, title: pageTitle)
        let systemPrompt = DinoAgentHarness.systemPrompt

        var messages: [[String: Any]] = [
            ["role": "system", "content": systemPrompt],
            ["role": "user", "content": "Goal: \(goal)\n\nPage State:\n\(framedDOM)"]
        ]

        for item in history.suffix(6) {
            if let role = item["role"] as? String, let text = item["text"] as? String {
                messages.append(["role": role, "content": text])
            }
        }

        let openAITools = Self.browserTools.map { tool -> [String: Any] in
            [
                "type": "function",
                "function": [
                    "name": tool["name"] as? String ?? "",
                    "description": tool["description"] as? String ?? "",
                    "parameters": tool["parameters"] as? [String: Any] ?? [:]
                ]
            ]
        }

        let payload: [String: Any] = [
            "model": model,
            "messages": messages,
            "tools": openAITools,
            "temperature": 0.2
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let msg = String(data: data, encoding: .utf8) ?? "HTTP \( (response as? HTTPURLResponse)?.statusCode ?? 500)"
            throw DinoLLMError.invalidResponse(msg)
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let first = choices.first,
              let message = first["message"] as? [String: Any] else {
            throw DinoLLMError.invalidResponse("Malformed OpenAI-compatible response")
        }

        var thought = (message["content"] as? String) ?? ""
        if thought.isEmpty, let reasoning = message["reasoning"] as? String {
            thought = reasoning
        } else if thought.isEmpty, let reasoningContent = message["reasoning_content"] as? String {
            thought = reasoningContent
        }
        var toolCall: AgentToolCall? = nil

        if let toolCalls = message["tool_calls"] as? [[String: Any]], let firstCall = toolCalls.first,
           let function = firstCall["function"] as? [String: Any],
           let name = function["name"] as? String,
           let argStr = function["arguments"] as? String,
           let argData = argStr.data(using: .utf8),
           let args = try? JSONSerialization.jsonObject(with: argData) as? [String: Any] {
            toolCall = AgentToolCall(name: name, arguments: args)
        }

        return AgentStepResponse(thought: thought.trimmingCharacters(in: .whitespacesAndNewlines), toolCall: toolCall)
    }
}
