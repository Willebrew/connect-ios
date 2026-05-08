//
//  ProductionAPIClient.swift
//  connect-ios
//
//  Created by Will Killebrew on 11/11/25.
//
//  Production API client for real comma.ai API calls
//

import Foundation

final class ProductionAPIClient: APIClient {
    private var authToken: String?
    private var onUnauthorized: (() -> Void)?

    init() {}

    func setAuthToken(_ token: String) {
        self.authToken = token
        if let expiration = try? JWTHelper.getExpirationDate(from: token) {
            Logger.auth.debug("Stored auth token (prefix: \(Logger.redact(token: token))) expiring at \(expiration)")
        } else {
            Logger.auth.debug("Stored auth token (unable to parse expiration)")
        }
    }

    func setUnauthorizedHandler(_ handler: @escaping () -> Void) {
        self.onUnauthorized = handler
    }

    /// Validates that the current token is not expired
    private func validateToken() throws {
        guard let token = authToken else {
            throw APIError.unauthorized
        }

        if JWTHelper.isTokenExpired(token) {
            Logger.auth.error("Token has expired")
            throw APIError.unauthorized
        }
    }

    private func makeRequest<T: Decodable>(
        url: URL,
        method: String = "GET",
        body: Data? = nil
    ) async throws -> T {
        // Check token validity before making request
        if authToken != nil {
            do {
                try validateToken()
            } catch APIError.unauthorized {
                // Token is expired, trigger logout
                onUnauthorized?()
                throw APIError.unauthorized
            }
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        request.cachePolicy = .reloadIgnoringLocalCacheData // Always fetch fresh data

        if let token = authToken {
            request.setValue("JWT \(token)", forHTTPHeaderField: "Authorization")
        }

        if body != nil {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        if let url = request.url {
            Logger.api.debug("\(method) \(Logger.redactURL(url))")
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw APIError.noData
            }

            if httpResponse.statusCode == 401 {
                Logger.auth.error("Received 401 Unauthorized")
                // Trigger logout on 401
                onUnauthorized?()
                throw APIError.unauthorized
            }

            guard (200...299).contains(httpResponse.statusCode) else {
                let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
                throw APIError.serverError(httpResponse.statusCode, errorMessage)
            }

            let decoder = JSONDecoder()
            return try decoder.decode(T.self, from: data)
        } catch let error as DecodingError {
            throw APIError.decodingError(error)
        } catch let error as APIError {
            throw error
        } catch {
            throw APIError.networkError(error)
        }
    }

    // MARK: - Auth

    /// Exchanges an already-processed OAuth code (from embedded web view callback) for a JWT token
    /// Use this when the code has already been processed through comma.ai's redirect endpoint
    func exchangeToken(code: String, provider: String) async throws -> String {
        Logger.auth.debug("Exchanging processed OAuth code (prefix: \(code.prefix(20))...) for JWT token, provider: \(provider)")

        let token = try await performTokenExchange(code: code, provider: provider)
        self.setAuthToken(token)
        return token
    }

    /// Authenticates with a raw OAuth code by processing it through comma.ai's redirect endpoint
    /// Use this for native OAuth flows where you receive the raw code directly from the provider
    func authenticate(code: String, provider: String, state: String?) async throws -> String {
        // Mobile apps can't use comma.ai's web redirect flow
        // So we manually call the redirect endpoint to process the raw OAuth code
        Logger.auth.debug("Processing raw OAuth code (prefix: \(code.prefix(20))...) through redirect endpoint, provider: \(provider), state: \(state ?? "none")")

        // Map provider to comma.ai's endpoint code
        let providerCode: String
        switch provider.lowercased() {
        case "google": providerCode = "g"
        case "github": providerCode = "h"
        case "apple": providerCode = "a"
        default: providerCode = provider.lowercased().prefix(1).description
        }

        // Call comma.ai's redirect endpoint with the raw OAuth code
        var redirectComponents = URLComponents(string: "\(APIConstants.commaURLRoot)v2/auth/\(providerCode)/redirect/")!
        var redirectQuery = [URLQueryItem(name: "code", value: code)]
        if let state = state {
            redirectQuery.append(URLQueryItem(name: "state", value: state))
        }
        redirectComponents.queryItems = redirectQuery

        guard let url = redirectComponents.url else {
            throw APIError.invalidURL
        }

        Logger.auth.debug("Calling: \(url.absoluteString)")

        // Use custom delegate to capture redirect without following it
        let redirectDelegate = RedirectCaptureDelegate()
        let session = URLSession(configuration: .default, delegate: redirectDelegate, delegateQueue: nil)

        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        do {
            let (data, response) = try await session.data(for: request)

            // Check if we captured a redirect
            if let redirectLocation = redirectDelegate.redirectLocation {
                Logger.auth.debug("Captured redirect to: \(redirectLocation)")

                // Extract processed code from redirect URL
                guard let redirectURL = URL(string: redirectLocation),
                      let components = URLComponents(url: redirectURL, resolvingAgainstBaseURL: true),
                      let queryItems = components.queryItems,
                      let processedCode = queryItems.first(where: { $0.name == "code" })?.value else {
                    Logger.auth.error("Failed to extract code from redirect")
                    throw APIError.serverError(500, "Failed to parse redirect")
                }

                let extractedProvider = queryItems.first(where: { $0.name == "provider" })?.value ?? provider

                Logger.auth.debug("Extracted processed code (prefix: \(processedCode.prefix(20))...) for provider: \(extractedProvider)")

                // Now exchange the processed code for JWT token
                let token = try await self.performTokenExchange(code: processedCode, provider: extractedProvider)
                self.setAuthToken(token)
                return token

            } else {
                // No redirect captured - this is an error
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw APIError.noData
                }

                Logger.auth.error("No redirect captured - Status: \(httpResponse.statusCode)")
                throw APIError.serverError(httpResponse.statusCode, "No redirect from comma.ai")
            }
        } catch {
            Logger.auth.error("OAuth authentication error", error: error)
            throw error
        }
    }

    // Separate function for token exchange
    private func performTokenExchange(code: String, provider: String) async throws -> String {

        // STEP 2: Now use the processed code for token exchange (same as webapp)
        let tokenURL = "\(APIConstants.commaURLRoot)v2/auth/"
        guard let tokenExchangeURL = URL(string: tokenURL) else {
            throw APIError.invalidURL
        }

        Logger.auth.debug("Sending token exchange request to \(tokenURL), code prefix: \(code.prefix(20))..., provider: \(provider)")

        // Prepare form data body (application/x-www-form-urlencoded)
        // Matches webapp: { code, provider }
        var tokenComponents = URLComponents()
        tokenComponents.queryItems = [
            URLQueryItem(name: "code", value: code),
            URLQueryItem(name: "provider", value: provider)
        ]

        guard let formBody = tokenComponents.query?.data(using: .utf8) else {
            throw APIError.noData
        }

        var request = URLRequest(url: tokenExchangeURL)
        request.httpMethod = "POST"
        request.httpBody = formBody
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw APIError.noData
            }

            guard (200...299).contains(httpResponse.statusCode) else {
                let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
                Logger.auth.error("Token exchange failed - Status: \(httpResponse.statusCode)")
                throw APIError.serverError(httpResponse.statusCode, errorMessage)
            }

            Logger.auth.debug("Token exchange successful")

            // Parse response - expect {"access_token": "jwt_token_here"}
            struct TokenResponse: Codable {
                let accessToken: String?
                let access_token: String?

                var token: String? {
                    return accessToken ?? access_token
                }
            }

            let decoder = JSONDecoder()
            let tokenResponse = try decoder.decode(TokenResponse.self, from: data)

            guard let token = tokenResponse.token else {
                throw APIError.serverError(500, "No access token in response")
            }

            return token
        } catch let error as DecodingError {
            throw APIError.decodingError(error)
        } catch let error as APIError {
            throw error
        } catch {
            throw APIError.networkError(error)
        }
    }

    func getProfile() async throws -> UserProfile {
        Logger.api.debug("Fetching user profile")
        guard let url = URL(string: "\(APIConstants.commaURLRoot)v1/me/") else {
            throw APIError.invalidURL
        }
        return try await makeRequest(url: url)
    }

    // MARK: - Devices

    func listDevices() async throws -> [Device] {
        guard let url = URL(string: "\(APIConstants.commaURLRoot)v1/me/devices/") else {
            throw APIError.invalidURL
        }
        return try await makeRequest(url: url)
    }

    func fetchDevice(dongleId: String) async throws -> Device {
        guard let url = URL(string: "\(APIConstants.commaURLRoot)v1/devices/\(dongleId)") else {
            throw APIError.invalidURL
        }
        return try await makeRequest(url: url)
    }

    func fetchDeviceStats(dongleId: String) async throws -> DeviceStats {
        guard let url = URL(string: "\(APIConstants.commaURLRoot)v1.1/devices/\(dongleId)/stats") else {
            throw APIError.invalidURL
        }
        return try await makeRequest(url: url)
    }

    func pairDevice(token: String) async throws -> Device {
        guard let url = URL(string: "\(APIConstants.commaURLRoot)v1/devices/") else {
            throw APIError.invalidURL
        }
        let body = try JSONEncoder().encode(["pair_token": token])
        return try await makeRequest(url: url, method: "POST", body: body)
    }

    func unpairDevice(dongleId: String) async throws {
        guard let url = URL(string: "\(APIConstants.commaURLRoot)v1/devices/\(dongleId)/unpair") else {
            throw APIError.invalidURL
        }

        struct UnpairResponse: Decodable {
            let success: Int
            let error: String?
        }

        let response: UnpairResponse = try await makeRequest(url: url, method: "POST")

        if response.success == 0, let error = response.error {
            throw APIError.serverError(400, error)
        }
    }

    func setDeviceAlias(dongleId: String, alias: String) async throws -> Device {
        guard let url = URL(string: "\(APIConstants.commaURLRoot)v1/devices/\(dongleId)/") else {
            throw APIError.invalidURL
        }
        let body = try JSONEncoder().encode(["alias": alias])
        return try await makeRequest(url: url, method: "PATCH", body: body)
    }

    func shareDevice(dongleId: String, userIdentifier: String) async throws {
        guard let url = URL(string: "\(APIConstants.commaURLRoot)v1/devices/\(dongleId)/add_user") else {
            throw APIError.invalidURL
        }

        struct ShareRequest: Encodable {
            let email: String
        }

        let body = try JSONEncoder().encode(ShareRequest(email: userIdentifier))

        struct ShareResponse: Decodable {
            // API may return empty object or success field
        }

        let _: ShareResponse = try await makeRequest(url: url, method: "POST", body: body)
    }

    // MARK: - Routes

    func fetchRoutes(dongleId: String, start: Date, end: Date, limit: Int) async throws -> [Route] {
        let startMs = Int(start.timeIntervalSince1970 * 1000)
        let endMs = Int(end.timeIntervalSince1970 * 1000)
        guard let url = URL(string: "\(APIConstants.commaURLRoot)v1/devices/\(dongleId)/routes_segments?start=\(startMs)&end=\(endMs)&limit=\(limit)") else {
            throw APIError.invalidURL
        }
        return try await makeRequest(url: url)
    }

    func getPreservedRoutes(dongleId: String) async throws -> [Route] {
        guard let url = URL(string: "\(APIConstants.commaURLRoot)v1/devices/\(dongleId)/routes?preserved=true") else {
            throw APIError.invalidURL
        }
        return try await makeRequest(url: url)
    }

    func setRoutePublic(fullname: String, isPublic: Bool) async throws {
        guard let encoded = fullname.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "\(APIConstants.commaURLRoot)v1/route/\(encoded)/") else {
            throw APIError.invalidURL
        }
        let body = try JSONEncoder().encode(["is_public": isPublic])
        let _: RouteActionResponse = try await makeRequest(url: url, method: "PATCH", body: body)
    }

    func setRoutePreserved(fullname: String, preserved: Bool) async throws {
        guard let encoded = fullname.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "\(APIConstants.commaURLRoot)v1/route/\(encoded)/preserve") else {
            throw APIError.invalidURL
        }
        if preserved {
            let _: RouteActionResponse = try await makeRequest(url: url, method: "POST")
        } else {
            let _: RouteActionResponse = try await makeRequest(url: url, method: "DELETE")
        }
    }

    // MARK: - Athena

    func sendAthenaCommand(dongleId: String, method: String, params: [String: Any]?) async throws -> [String: Any] {
        guard let url = URL(string: "\(APIConstants.athenaURLRoot)\(dongleId)") else {
            throw APIError.invalidURL
        }

        // Ensure we have a valid token, mirroring makeRequest() handling
        if authToken != nil {
            do {
                try validateToken()
            } catch APIError.unauthorized {
                onUnauthorized?()
                throw APIError.unauthorized
            }
        } else {
            throw APIError.unauthorized
        }

        var payload: [String: Any] = [
            "method": method,
            "jsonrpc": "2.0",
            "id": 0
        ]
        if let params = params {
            payload["params"] = params
        }

        let body = try JSONSerialization.data(withJSONObject: payload)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = authToken {
            request.setValue("JWT \(token)", forHTTPHeaderField: "Authorization")
        }

        if let url = request.url {
            Logger.api.debug("Athena POST \(Logger.redactURL(url))")
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw APIError.noData
            }

            if httpResponse.statusCode == 401 {
                onUnauthorized?()
                throw APIError.unauthorized
            }

            guard (200...299).contains(httpResponse.statusCode) else {
                let bodyString = String(data: data, encoding: .utf8) ?? "Unknown error"
                throw APIError.serverError(httpResponse.statusCode, bodyString)
            }

            let jsonObject: Any
            do {
                jsonObject = try JSONSerialization.jsonObject(with: data)
            } catch {
                throw APIError.decodingError(error)
            }

            guard let json = jsonObject as? [String: Any] else {
                let context = DecodingError.Context(codingPath: [], debugDescription: "Invalid Athena response format")
                throw APIError.decodingError(DecodingError.dataCorrupted(context))
            }

            if let errorObject = json["error"] as? [String: Any] {
                let errorCode = errorObject["code"] as? Int ?? httpResponse.statusCode
                let message = errorObject["message"] as? String ?? "Athena command failed"
                throw APIError.serverError(errorCode, message)
            }

            return json
        } catch let error as APIError {
            throw error
        } catch {
            throw APIError.networkError(error)
        }
    }

    func getUploadQueue(dongleId: String) async throws -> [[String: Any]] {
        let response = try await sendAthenaCommand(dongleId: dongleId, method: "listUploadQueue", params: nil)
        let result = response["result"] as? [String: Any]
        return result?["queue"] as? [[String: Any]] ?? []
    }

    func takeSnapshot(dongleId: String) async throws -> SnapshotResult {
        let response = try await sendAthenaCommand(dongleId: dongleId, method: "takeSnapshot", params: nil)
        let result = response["result"] as? [String: Any]

        let jpegBack = result?["jpegBack"] as? String ?? result?["jpeg_back"] as? String
        let jpegFront = result?["jpegFront"] as? String ?? result?["jpeg_front"] as? String

        // At least one image must be present
        if (jpegBack == nil || jpegBack!.isEmpty) && (jpegFront == nil || jpegFront!.isEmpty) {
            throw APIError.noData
        }

        return SnapshotResult(jpegBack: jpegBack, jpegFront: jpegFront)
    }

    // MARK: - Video

    func getVideoStreamURL(for route: Route) async throws -> URL {
        if let sig = route.shareSig,
           let expString = route.shareExp,
           let expValue = Int(expString),
           let url = try? buildVideoURL(fullname: route.fullname, sig: sig, exp: expValue) {
            return url
        }

        let signature = try await fetchShareSignature(for: route.fullname)
        route.shareSig = signature.sig
        route.shareExp = String(signature.exp)
        return try buildVideoURL(fullname: route.fullname, sig: signature.sig, exp: signature.exp)
    }
    
    /// Gets a video stream URL for a specific camera angle
    /// - Parameters:
    ///   - route: The route to get video for
    ///   - camera: The camera angle to fetch (road, driver, or wide)
    /// - Returns: The HLS stream URL for the specified camera
    func getVideoStreamURL(for route: Route, camera: CameraStreamType) async throws -> URL {
        let signature = try await fetchShareSignature(for: route.fullname)
        route.shareSig = signature.sig
        route.shareExp = String(signature.exp)
        return try buildVideoURL(fullname: route.fullname, sig: signature.sig, exp: signature.exp, camera: camera)
    }

    /// Generates a video URL for a specific segment
    func getSegmentVideoURL(fullname: String, segmentNumber: Int) async throws -> URL {
        // Segment-specific video URL (if needed for multi-segment playback)
        let segmentFullname = "\(fullname)/\(segmentNumber)"
        let dummyRoute = Route(fullname: segmentFullname, logId: segmentFullname, dongleId: "")
        return try await getVideoStreamURL(for: dummyRoute)
    }

    // MARK: - Files

    func getRouteFiles(routeName: String) async throws -> [String: [String]] {
        guard let encodedName = routeName.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "\(APIConstants.commaURLRoot)v1/route/\(encodedName)/files") else {
            throw APIError.invalidURL
        }
        return try await makeRequest(url: url)
    }

    func fetchRouteEvents(route: Route) async throws -> [DriveEvent] {
        guard !route.url.isEmpty else {
            Logger.data.error("Route URL is empty for \(route.fullname)")
            return []
        }
        let segments = max(route.maxqlog, 0)
        Logger.data.debug("Fetching events for \(route.fullname): \(segments + 1) segments")
        var rawEvents: [RawRouteEvent] = []

        await withTaskGroup(of: [RawRouteEvent].self) { group in
            for index in 0...segments {
                guard let url = URL(string: "\(route.url)/\(index)/events.json") else {
                    Logger.data.error("Invalid events URL: \(route.url)/\(index)/events.json")
                    continue
                }
                group.addTask {
                    do {
                        return try await self.fetchJSONIfAvailable(from: url) ?? []
                    } catch {
                        if !error.isCancellationError {
                            Logger.data.error("Failed to fetch events for \(route.fullname) segment \(index)", error: error)
                        }
                        return []
                    }
                }
            }

            for await events in group {
                rawEvents.append(contentsOf: events)
            }
        }

        Logger.data.debug("Fetched \(rawEvents.count) events for \(route.fullname)")
        return parseEvents(from: rawEvents, routeDuration: route.duration)
    }

    func fetchDriveCoordinates(route: Route) async throws -> [Int: Coordinate] {
        guard !route.url.isEmpty else { return [:] }
        let segments = max(route.maxqlog, 0)
        var allSamples: [[RawDriveCoordinate]] = []

        await withTaskGroup(of: [RawDriveCoordinate].self) { group in
            for index in 0...segments {
                guard let url = URL(string: "\(route.url)/\(index)/coords.json") else { continue }
                group.addTask {
                    do {
                        return try await self.fetchJSONIfAvailable(from: url) ?? []
                    } catch {
                        if !error.isCancellationError {
                            Logger.data.error("Failed to fetch coordinates for \(route.fullname) segment \(index)", error: error)
                        }
                        return []
                    }
                }
            }

            for await samples in group {
                allSamples.append(samples)
            }
        }

        let merged = allSamples.flatMap { $0 }
        return merged.reduce(into: [Int: Coordinate]()) { dict, sample in
            dict[sample.t] = Coordinate(latitude: sample.lat, longitude: sample.lng)
        }
    }

    func getUploadURLs(dongleId: String, paths: [String], expiryDays: Int) async throws -> [UploadURLResponse] {
        guard let url = URL(string: "\(APIConstants.commaURLRoot)v1/\(dongleId)/upload_urls/") else {
            throw APIError.invalidURL
        }
        struct UploadURLRequest: Encodable {
            let paths: [String]
            let expiry_days: Int
        }
        let payload = UploadURLRequest(paths: paths, expiry_days: expiryDays)
        let body = try JSONEncoder().encode(payload)
        return try await makeRequest(url: url, method: "POST", body: body)
    }

    func checkFileAvailability(routeName: String, fileType: FileType) async throws -> FileAvailabilityStatus {
        // Get all files for the route
        let files = try await getRouteFiles(routeName: routeName)
        
        // Check if the requested file type exists
        guard let fileURLs = files[fileType.rawValue], !fileURLs.isEmpty else {
            return .notAvailable
        }
        
        // For routes, we expect one file per segment
        // Parse the route to get expected segment count
        let segmentCount = fileURLs.count
        
        // All files are available
        if segmentCount > 0 {
            return .available(urls: fileURLs)
        }
        
        return .notAvailable
    }

    // MARK: - Billing

    func getSubscription(dongleId: String) async throws -> Subscription? {
        guard let url = URL(string: "\(APIConstants.billingURLRoot)v1/devices/\(dongleId)/subscription") else {
            throw APIError.invalidURL
        }
        do {
            return try await makeRequest(url: url)
        } catch APIError.serverError(404, _) {
            return nil
        }
    }

    func getSubscribeInfo(dongleId: String) async throws -> SubscribeInfo {
        guard let url = URL(string: "\(APIConstants.billingURLRoot)v1/devices/\(dongleId)/subscribe_info") else {
            throw APIError.invalidURL
        }
        return try await makeRequest(url: url)
    }

    func fetchDeviceLocation(dongleId: String) async throws -> DeviceLocationResponse {
        guard let url = URL(string: "\(APIConstants.commaURLRoot)v1/devices/\(dongleId)/location") else {
            throw APIError.invalidURL
        }
        return try await makeRequest(url: url)
    }

    // MARK: - Geocoding

    func reverseGeocode(latitude: Double, longitude: Double) async throws -> Location {
        let urlString = "https://api.mapbox.com/geocoding/v5/mapbox.places/\(longitude),\(latitude).json?access_token=\(APIConstants.mapboxToken)"
        guard let url = URL(string: urlString) else {
            throw APIError.invalidURL
        }

        struct MapboxResponse: Codable {
            var features: [Feature]
            struct Feature: Codable {
                var placeName: String
                var text: String
                enum CodingKeys: String, CodingKey {
                    case placeName = "place_name"
                    case text
                }
            }
        }

        let response: MapboxResponse = try await makeRequest(url: url)
        if let feature = response.features.first {
            return Location(place: feature.text, details: feature.placeName)
        }
        return Location(place: "Unknown Location", details: "")
    }
}

// MARK: - Private Helpers

private extension ProductionAPIClient {
    static let signatureQueryAllowed: CharacterSet = {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "+/=")
        return allowed
    }()

    struct RouteActionResponse: Decodable {
        let success: Int?
        let is_public: Bool?
        let preserved: Bool?
    }

    struct RawRouteEvent: Decodable {
        let type: String
        let routeOffsetMillis: TimeInterval
        let routeOffsetNanos: Int?
        let data: RawRouteEventData

        enum CodingKeys: String, CodingKey {
            case type
            case routeOffsetMillis = "route_offset_millis"
            case routeOffsetNanos = "route_offset_nanos"
            case data
        }
    }

    struct RawRouteEventData: Decodable {
        let state: String?
        let eventType: String?
        let alertStatus: String?
        let endRouteOffsetMillis: TimeInterval?
        let enabled: Bool?

        enum CodingKeys: String, CodingKey {
            case state
            case eventType = "event_type"
            case alertStatus
            case endRouteOffsetMillis = "end_route_offset_millis"
            case enabled
        }

        init(state: String? = nil,
             eventType: String? = nil,
             alertStatus: String? = nil,
             endRouteOffsetMillis: TimeInterval? = nil,
             enabled: Bool? = nil) {
            self.state = state
            self.eventType = eventType
            self.alertStatus = alertStatus
            self.endRouteOffsetMillis = endRouteOffsetMillis
            self.enabled = enabled
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            state = try container.decodeIfPresent(String.self, forKey: .state)
            eventType = try container.decodeIfPresent(String.self, forKey: .eventType)
            endRouteOffsetMillis = try container.decodeIfPresent(TimeInterval.self, forKey: .endRouteOffsetMillis)
            enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled)

            if let stringStatus = try? container.decode(String.self, forKey: .alertStatus) {
                alertStatus = stringStatus
            } else if let intStatus = try? container.decode(Int.self, forKey: .alertStatus) {
                alertStatus = RawRouteEventData.alertStatusString(from: intStatus)
            } else if let doubleStatus = try? container.decode(Double.self, forKey: .alertStatus) {
                alertStatus = RawRouteEventData.alertStatusString(from: Int(doubleStatus))
            } else {
                alertStatus = nil
            }
        }

        private static func alertStatusString(from code: Int) -> String? {
            switch code {
            case 0: return "normal"
            case 1: return "userPrompt"
            case 2: return "critical"
            default: return String(code)
            }
        }
    }

    struct RawDriveCoordinate: Decodable {
        let t: Int
        let lat: Double
        let lng: Double
    }

    struct ShareSignatureResponse: Decodable {
        let sig: String
        let exp: Int

        enum CodingKeys: String, CodingKey {
            case sig
            case exp
        }

        init(sig: String, exp: Int) {
            self.sig = sig
            self.exp = exp
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            sig = try container.decode(String.self, forKey: .sig)

            if let intValue = try? container.decode(Int.self, forKey: .exp) {
                exp = intValue
            } else if let stringValue = try? container.decode(String.self, forKey: .exp),
                      let parsed = Int(stringValue) {
                exp = parsed
            } else {
                throw DecodingError.dataCorruptedError(
                    forKey: .exp,
                    in: container,
                    debugDescription: "Expected exp to decode as Int or numeric String."
                )
            }
        }
    }

    func fetchJSONIfAvailable<T: Decodable>(from url: URL) async throws -> T? {
        let (data, response) = try await URLSession.shared.data(for: URLRequest(url: url))
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.noData
        }

        switch httpResponse.statusCode {
        case 200...299:
            if data.isEmpty {
                return nil
            }
            let decoder = JSONDecoder()
            return try decoder.decode(T.self, from: data)
        case 404:
            return nil
        default:
            let body = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw APIError.serverError(httpResponse.statusCode, body)
        }
    }

    func fetchShareSignature(for route: String) async throws -> ShareSignatureResponse {
        guard let encoded = route.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "\(APIConstants.commaURLRoot)v1/route/\(encoded)/share_signature") else {
            throw APIError.invalidURL
        }
        return try await makeRequest(url: url)
    }

    func buildVideoURL(fullname: String, sig: String, exp: Int, camera: CameraStreamType = .road) throws -> URL {
        guard let encodedFullname = fullname.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
            throw APIError.invalidURL
        }

        var components = URLComponents(string: "\(APIConstants.commaURLRoot)v1/route/\(encodedFullname)/\(camera.hlsFilename)")

        let encodedSig = sig.addingPercentEncoding(withAllowedCharacters: Self.signatureQueryAllowed) ?? sig
        components?.percentEncodedQuery = "exp=\(exp)&sig=\(encodedSig)"

        guard let url = components?.url else {
            throw APIError.invalidURL
        }
        return url
    }

    func parseEvents(from rawEvents: [RawRouteEvent], routeDuration: TimeInterval) -> [DriveEvent] {
        guard !rawEvents.isEmpty else { return [] }

        let sorted = rawEvents.sorted { lhs, rhs in
            if lhs.routeOffsetMillis == rhs.routeOffsetMillis {
                return (lhs.routeOffsetNanos ?? 0) < (rhs.routeOffsetNanos ?? 0)
            }
            return lhs.routeOffsetMillis < rhs.routeOffsetMillis
        }

        var result: [DriveEvent] = []
        var currentEngageIndex: Int?
        var currentAlertIndex: Int?
        var currentOverrideIndex: Int?
        var lastManualEngageIndex: Int?

        func closeEvent(at index: inout Int?, endOffset: TimeInterval) {
            guard let idx = index else { return }
            result[idx].data.endRouteOffsetMillis = endOffset
            index = nil
        }

        for raw in sorted {
            switch raw.type {
            case "state":
                let enabled = raw.data.enabled ?? false

                if !enabled {
                    closeEvent(at: &currentEngageIndex, endOffset: raw.routeOffsetMillis)
                } else if currentEngageIndex == nil {
                    let event = DriveEvent(
                        type: .engage,
                        routeOffsetMillis: raw.routeOffsetMillis,
                        data: DriveEvent.EventData(state: raw.data.state)
                    )
                    result.append(event)
                    currentEngageIndex = result.count - 1
                }

                let alertStatus = alertStatus(from: raw.data.alertStatus)
                if alertStatus == nil || alertStatus == .normal {
                    closeEvent(at: &currentAlertIndex, endOffset: raw.routeOffsetMillis)
                } else if currentAlertIndex == nil {
                    let event = DriveEvent(
                        type: .alert,
                        routeOffsetMillis: raw.routeOffsetMillis,
                        data: DriveEvent.EventData(
                            state: raw.data.state,
                            alertStatus: alertStatus
                        )
                    )
                    result.append(event)
                    currentAlertIndex = result.count - 1
                }

                let state = raw.data.state ?? ""
                if state != "overriding" && state != "preEnabled" {
                    closeEvent(at: &currentOverrideIndex, endOffset: raw.routeOffsetMillis)
                } else if currentOverrideIndex == nil {
                    let event = DriveEvent(
                        type: .overriding,
                        routeOffsetMillis: raw.routeOffsetMillis,
                        data: DriveEvent.EventData(state: state)
                    )
                    result.append(event)
                    currentOverrideIndex = result.count - 1
                }

            case "engage":
                let event = DriveEvent(
                    type: .engage,
                    routeOffsetMillis: raw.routeOffsetMillis,
                    data: DriveEvent.EventData()
                )
                result.append(event)
                lastManualEngageIndex = result.count - 1
            case "disengage":
                if let idx = lastManualEngageIndex {
                    result[idx].data.endRouteOffsetMillis = raw.routeOffsetMillis
                }
                lastManualEngageIndex = nil
            case "alert":
                let event = DriveEvent(
                    type: .alert,
                    routeOffsetMillis: raw.routeOffsetMillis,
                    data: DriveEvent.EventData(alertStatus: alertStatus(from: raw.data.alertStatus))
                )
                result.append(event)
            case "event":
                let event = DriveEvent(
                    type: .event,
                    routeOffsetMillis: raw.routeOffsetMillis,
                    data: DriveEvent.EventData(
                        state: raw.data.state,
                        eventType: raw.data.eventType
                    )
                )
                result.append(event)
            case "user_bookmark", "user_flag":
                let event = DriveEvent(
                    type: .bookmark,
                    routeOffsetMillis: raw.routeOffsetMillis,
                    data: DriveEvent.EventData(
                        endRouteOffsetMillis: raw.routeOffsetMillis + 1_000
                    )
                )
                result.append(event)
            default:
                continue
            }
        }

        if routeDuration > 0 {
            closeEvent(at: &currentEngageIndex, endOffset: routeDuration)
            closeEvent(at: &currentAlertIndex, endOffset: routeDuration)
            closeEvent(at: &currentOverrideIndex, endOffset: routeDuration)
            if let idx = lastManualEngageIndex,
               result[idx].data.endRouteOffsetMillis == nil {
                result[idx].data.endRouteOffsetMillis = routeDuration
            }
        }
        return result
    }

    func alertStatus(from rawValue: String?) -> DriveEvent.EventData.AlertStatus? {
        guard var rawValue else { return nil }
        rawValue = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)

        if let numeric = Int(rawValue) {
            return alertStatus(fromNumericCode: numeric)
        }

        switch rawValue.lowercased() {
        case "normal": return .normal
        case "userprompt": return .userPrompt
        case "critical": return .critical
        default: return DriveEvent.EventData.AlertStatus(rawValue: rawValue)
        }
    }

    func alertStatus(fromNumericCode code: Int) -> DriveEvent.EventData.AlertStatus? {
        switch code {
        case 0: return .normal
        case 1: return .userPrompt
        case 2: return .critical
        default: return nil
        }
    }
}
