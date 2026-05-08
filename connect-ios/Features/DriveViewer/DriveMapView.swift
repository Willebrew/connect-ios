//
//  DriveMapView.swift
//  connect-ios
//
//  Created by Will Killebrew on 11/11/25.
//
//  Interactive map with route path and real-time position
//  Uses UIKit MKMapView for smooth 60fps annotation updates
//

import SwiftUI
import MapKit
import CoreLocation

struct DriveMapView: View {
    let route: Route
    @Bindable var playbackState: PlaybackState

    @State private var isFollowing = true
    @State private var cameraHeading: CLLocationDirection = 0
    @State private var sortedCoordKeys: [Int] = []
    @AppStorage("map_lock_north") private var mapLockNorth = false
    @AppStorage("map_color_coded_route") private var mapColorCodedRoute = false

    var body: some View {
        DriveMapViewRepresentable(
            route: route,
            playbackState: playbackState,
            isFollowing: $isFollowing,
            cameraHeading: $cameraHeading,
            mapLockNorth: mapLockNorth,
            mapColorCodedRoute: mapColorCodedRoute,
            sortedCoordKeys: $sortedCoordKeys
        )
        .overlay(alignment: .topTrailing) {
            if !isFollowing {
                VStack(spacing: 10) {
                    Spacer()
                        .frame(height: 60)

                    MapControlButton(systemImage: "scope") {
                        isFollowing = true
                    }
                }
                .padding()
            }
        }
        .onAppear {
            if let coords = route.driveCoords {
                sortedCoordKeys = coords.keys.sorted()
            }
        }
        .onChange(of: route.driveCoords?.count) { _, _ in
            if let coords = route.driveCoords {
                sortedCoordKeys = coords.keys.sorted()
            }
        }
    }
}

// MARK: - UIKit MKMapView Wrapper

struct DriveMapViewRepresentable: UIViewRepresentable {
    let route: Route
    @Bindable var playbackState: PlaybackState
    @Binding var isFollowing: Bool
    @Binding var cameraHeading: CLLocationDirection
    let mapLockNorth: Bool
    let mapColorCodedRoute: Bool
    @Binding var sortedCoordKeys: [Int]

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.mapType = .standard
        mapView.isRotateEnabled = true
        mapView.isPitchEnabled = true
        mapView.showsCompass = false
        mapView.showsScale = false
        
        // Add route overlay and markers
        context.coordinator.setupRoute(on: mapView, route: route, colorCoded: mapColorCodedRoute)
        
        // Add car annotation
        let carAnnotation = CarAnnotation(coordinate: CLLocationCoordinate2D(latitude: 0, longitude: 0))
        mapView.addAnnotation(carAnnotation)
        context.coordinator.carAnnotation = carAnnotation
        
        // Start display link for smooth updates
        context.coordinator.startDisplayLink()
        
        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        let coordinator = context.coordinator
        coordinator.playbackState = playbackState
        coordinator.isFollowing = isFollowing
        coordinator.mapLockNorth = mapLockNorth
        coordinator.sortedCoordKeys = sortedCoordKeys
        coordinator.route = route
        coordinator.cameraHeadingBinding = $cameraHeading
        coordinator.isFollowingBinding = $isFollowing
        
        // Update route if coordinates changed
        if coordinator.lastCoordCount != (route.driveCoords?.count ?? 0) {
            coordinator.setupRoute(on: mapView, route: route, colorCoded: mapColorCodedRoute)
            coordinator.lastCoordCount = route.driveCoords?.count ?? 0
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            playbackState: playbackState,
            isFollowing: isFollowing,
            cameraHeading: cameraHeading,
            mapLockNorth: mapLockNorth,
            sortedCoordKeys: sortedCoordKeys,
            route: route,
            cameraHeadingBinding: $cameraHeading,
            isFollowingBinding: $isFollowing
        )
    }

    static func dismantleUIView(_ uiView: MKMapView, coordinator: Coordinator) {
        coordinator.stopDisplayLink()
    }

    class Coordinator: NSObject, MKMapViewDelegate {
        var playbackState: PlaybackState
        var isFollowing: Bool
        var cameraHeading: CLLocationDirection
        var mapLockNorth: Bool
        var sortedCoordKeys: [Int]
        var route: Route
        var cameraHeadingBinding: Binding<CLLocationDirection>
        var isFollowingBinding: Binding<Bool>
        
        fileprivate var carAnnotation: CarAnnotation?
        var displayLink: CADisplayLink?
        weak var mapView: MKMapView?
        var lastCoordCount = 0
        var isUserInteracting = false
        
        private let cameraDistance: CLLocationDistance = 800
        private let cameraPitch: CGFloat = 65

        init(playbackState: PlaybackState,
             isFollowing: Bool,
             cameraHeading: CLLocationDirection,
             mapLockNorth: Bool,
             sortedCoordKeys: [Int],
             route: Route,
             cameraHeadingBinding: Binding<CLLocationDirection>,
             isFollowingBinding: Binding<Bool>) {
            self.playbackState = playbackState
            self.isFollowing = isFollowing
            self.cameraHeading = cameraHeading
            self.mapLockNorth = mapLockNorth
            self.sortedCoordKeys = sortedCoordKeys
            self.route = route
            self.cameraHeadingBinding = cameraHeadingBinding
            self.isFollowingBinding = isFollowingBinding
        }

        func startDisplayLink() {
            displayLink = CADisplayLink(target: self, selector: #selector(updateFrame))
            displayLink?.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
            displayLink?.add(to: .main, forMode: .common)
        }

        func stopDisplayLink() {
            displayLink?.invalidate()
            displayLink = nil
        }

        @objc private func updateFrame() {
            guard let mapView = mapView,
                  let carAnnotation = carAnnotation else { return }
            
            guard let anchor = currentAnchor() else { return }
            
            // Update car position directly - no SwiftUI state involved
            UIView.performWithoutAnimation {
                carAnnotation.coordinate = anchor.coordinate
            }
            
            // Update camera if following and not interacting
            if isFollowing && !isUserInteracting {
                let targetHeading = mapLockNorth ? 0 : anchor.heading
                
                // Adaptive smoothing
                let headingDelta = abs(shortestAngleDifference(from: cameraHeading, to: targetHeading))
                let alpha = headingDelta > 20 ? 0.25 : 0.12
                
                cameraHeading = smoothHeading(from: cameraHeading, to: targetHeading, alpha: alpha)
                cameraHeadingBinding.wrappedValue = cameraHeading
                
                let camera = MKMapCamera(
                    lookingAtCenter: anchor.coordinate,
                    fromDistance: cameraDistance,
                    pitch: cameraPitch,
                    heading: cameraHeading
                )
                mapView.setCamera(camera, animated: false)
            }
        }

        func setupRoute(on mapView: MKMapView, route: Route, colorCoded: Bool) {
            self.mapView = mapView
            
            // Remove existing overlays except car
            mapView.removeOverlays(mapView.overlays)
            
            // Remove existing annotations except car
            let nonCarAnnotations = mapView.annotations.filter { !($0 is CarAnnotation) }
            mapView.removeAnnotations(nonCarAnnotations)
            
            guard let coords = route.driveCoords, !coords.isEmpty else { return }
            
            let sortedKeys = coords.keys.sorted()
            let coordinates = sortedKeys.compactMap { coords[$0]?.clCoordinate }
            
            guard coordinates.count >= 2 else { return }
            
            if colorCoded, let events = route.events {
                // Add color-coded polylines
                let segments = colorCodedSegments(coords: coords, events: events, sortedKeys: sortedKeys)
                for segment in segments {
                    let polyline = ColoredPolyline(coordinates: segment.coordinates, count: segment.coordinates.count)
                    polyline.color = segment.color
                    mapView.addOverlay(polyline)
                }
            } else {
                // Simple green route
                let polyline = ColoredPolyline(coordinates: coordinates, count: coordinates.count)
                polyline.color = UIColor(Color.themeGreen)
                mapView.addOverlay(polyline)
            }
            
            // Add start marker
            if let start = coordinates.first {
                let startAnnotation = MarkerAnnotation(coordinate: start, markerType: .start)
                mapView.addAnnotation(startAnnotation)
            }
            
            // Add end marker
            if let end = coordinates.last {
                let endAnnotation = MarkerAnnotation(coordinate: end, markerType: .end)
                mapView.addAnnotation(endAnnotation)
            }
            
            // Initial camera position
            if isFollowing, let anchor = currentAnchor() {
                let camera = MKMapCamera(
                    lookingAtCenter: anchor.coordinate,
                    fromDistance: cameraDistance,
                    pitch: cameraPitch,
                    heading: cameraHeading
                )
                mapView.setCamera(camera, animated: false)
            } else {
                // Fit to route
                let polyline = MKPolyline(coordinates: coordinates, count: coordinates.count)
                mapView.setVisibleMapRect(
                    polyline.boundingMapRect,
                    edgePadding: UIEdgeInsets(top: 50, left: 50, bottom: 50, right: 50),
                    animated: false
                )
            }
        }

        // MARK: - MKMapViewDelegate

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let polyline = overlay as? ColoredPolyline {
                let renderer = MKPolylineRenderer(polyline: polyline)
                renderer.strokeColor = polyline.color
                renderer.lineWidth = 4
                return renderer
            }
            return MKOverlayRenderer(overlay: overlay)
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if let carAnnotation = annotation as? CarAnnotation {
                let identifier = "car"
                var view = mapView.dequeueReusableAnnotationView(withIdentifier: identifier)
                if view == nil {
                    view = MKAnnotationView(annotation: carAnnotation, reuseIdentifier: identifier)
                    view?.canShowCallout = false
                    
                    // Create car view
                    let carView = UIView(frame: CGRect(x: 0, y: 0, width: 36, height: 36))
                    carView.backgroundColor = UIColor(Color.themeGreen)
                    carView.layer.cornerRadius = 18
                    carView.layer.shadowColor = UIColor.black.cgColor
                    carView.layer.shadowOffset = CGSize(width: 0, height: 2)
                    carView.layer.shadowRadius = 4
                    carView.layer.shadowOpacity = 0.3
                    
                    let imageView = UIImageView(image: UIImage(systemName: "car.fill"))
                    imageView.tintColor = .white
                    imageView.contentMode = .scaleAspectFit
                    imageView.frame = CGRect(x: 8, y: 8, width: 20, height: 20)
                    carView.addSubview(imageView)
                    
                    view?.addSubview(carView)
                    view?.frame = carView.frame
                    view?.centerOffset = CGPoint(x: 0, y: 0)
                }
                view?.annotation = annotation
                return view
            }
            
            if let markerAnnotation = annotation as? MarkerAnnotation {
                let identifier = markerAnnotation.markerType == .start ? "start" : "end"
                var view = mapView.dequeueReusableAnnotationView(withIdentifier: identifier)
                if view == nil {
                    view = MKAnnotationView(annotation: markerAnnotation, reuseIdentifier: identifier)
                    view?.canShowCallout = false
                    
                    let markerView = UIView(frame: CGRect(x: 0, y: 0, width: 16, height: 16))
                    markerView.backgroundColor = markerAnnotation.markerType == .start ? .green : .red
                    markerView.layer.cornerRadius = 8
                    markerView.layer.borderColor = UIColor.white.cgColor
                    markerView.layer.borderWidth = 2
                    
                    view?.addSubview(markerView)
                    view?.frame = markerView.frame
                    view?.centerOffset = CGPoint(x: 0, y: 0)
                }
                view?.annotation = annotation
                return view
            }
            
            return nil
        }

        func mapView(_ mapView: MKMapView, regionWillChangeAnimated animated: Bool) {
            // Check if user initiated the change
            if let gestureRecognizers = mapView.subviews.first?.gestureRecognizers {
                for recognizer in gestureRecognizers {
                    if recognizer.state == .began || recognizer.state == .changed {
                        isUserInteracting = true
                        DispatchQueue.main.async {
                            self.isFollowingBinding.wrappedValue = false
                            self.isFollowing = false
                        }
                        return
                    }
                }
            }
        }

        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            isUserInteracting = false
        }

        // MARK: - Anchor Calculation

        private func currentAnchor() -> MapCameraAnchor? {
            anchor(for: playbackState.currentOffset)
        }

        private func anchor(for offset: TimeInterval) -> MapCameraAnchor? {
            guard let coords = route.driveCoords, !coords.isEmpty else { return nil }
            guard !sortedCoordKeys.isEmpty else { return nil }
            
            let exactSeconds = max(0, offset / 1000)
            let lowerIndex = sortedCoordKeys.lastIndex(where: { Double($0) <= exactSeconds }) ?? 0
            let upperIndex = min(lowerIndex + 1, sortedCoordKeys.count - 1)

            let lowerKey = sortedCoordKeys[lowerIndex]
            let upperKey = sortedCoordKeys[upperIndex]

            func coord(for key: Int) -> CLLocationCoordinate2D? {
                coords[key]?.clCoordinate
            }

            guard let lowerCoord = coord(for: lowerKey) else { return nil }
            guard let upperCoord = coord(for: upperKey) else {
                let headingTarget = sortedCoordKeys.dropFirst().first.flatMap(coord(for:)) ?? lowerCoord
                return MapCameraAnchor(coordinate: lowerCoord, heading: heading(from: lowerCoord, to: headingTarget))
            }

            if lowerKey == upperKey {
                return MapCameraAnchor(coordinate: lowerCoord, heading: heading(from: lowerCoord, to: upperCoord))
            }

            // Interpolate position
            let denominator = Double(upperKey - lowerKey)
            let fraction = min(1.0, max(0.0, (exactSeconds - Double(lowerKey)) / denominator))
            let lat = lowerCoord.latitude + (upperCoord.latitude - lowerCoord.latitude) * fraction
            let lng = lowerCoord.longitude + (upperCoord.longitude - lowerCoord.longitude) * fraction
            let interpolated = CLLocationCoordinate2D(latitude: lat, longitude: lng)

            let headingValue = stableHeading(from: lowerIndex, coords: coords, coord: coord)
            return MapCameraAnchor(coordinate: interpolated, heading: headingValue)
        }

        private func stableHeading(from currentIndex: Int, coords: [Int: Coordinate], coord: (Int) -> CLLocationCoordinate2D?) -> CLLocationDirection {
            guard let currentCoord = coord(sortedCoordKeys[currentIndex]) else { return cameraHeading }

            let lookaheadDistance = 3
            var targetIndex = min(currentIndex + lookaheadDistance, sortedCoordKeys.count - 1)

            while targetIndex <= sortedCoordKeys.count - 1 {
                if let targetCoord = coord(sortedCoordKeys[targetIndex]) {
                    let distance = distanceBetween(currentCoord, targetCoord)
                    if distance > 5.0 {
                        return heading(from: currentCoord, to: targetCoord)
                    }
                }
                targetIndex += 1
                if targetIndex > currentIndex + 10 {
                    break
                }
            }

            return cameraHeading
        }

        private func heading(from start: CLLocationCoordinate2D, to end: CLLocationCoordinate2D) -> CLLocationDirection {
            guard start.latitude != end.latitude || start.longitude != end.longitude else { return cameraHeading }

            let lat1 = start.latitude * .pi / 180
            let lat2 = end.latitude * .pi / 180
            let deltaLon = (end.longitude - start.longitude) * .pi / 180

            let y = sin(deltaLon) * cos(lat2)
            let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(deltaLon)
            var degreesHeading = atan2(y, x) * 180 / .pi
            if degreesHeading < 0 {
                degreesHeading += 360
            }
            return degreesHeading
        }

        private func distanceBetween(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> CLLocationDistance {
            let first = CLLocation(latitude: a.latitude, longitude: b.longitude)
            let second = CLLocation(latitude: b.latitude, longitude: b.longitude)
            return first.distance(from: second)
        }

        private func shortestAngleDifference(from current: CLLocationDirection, to target: CLLocationDirection) -> Double {
            var delta = target - current
            if delta > 180 { delta -= 360 }
            else if delta < -180 { delta += 360 }
            return delta
        }

        private func smoothHeading(from current: CLLocationDirection, to target: CLLocationDirection, alpha: Double) -> CLLocationDirection {
            let delta = shortestAngleDifference(from: current, to: target)
            var newHeading = current + delta * alpha
            if newHeading < 0 { newHeading += 360 }
            else if newHeading >= 360 { newHeading -= 360 }
            return newHeading
        }

        private func colorCodedSegments(coords: [Int: Coordinate], events: [DriveEvent], sortedKeys: [Int]) -> [RouteSegmentData] {
            var segments: [RouteSegmentData] = []
            var currentSegment: [CLLocationCoordinate2D] = []
            var currentColor: UIColor?
            var lastCoordinate: CLLocationCoordinate2D?

            for key in sortedKeys {
                guard let coord = coords[key] else { continue }
                let offsetMillis = Double(key) * 1000
                let clCoord = coord.clCoordinate
                let color = colorForOffset(offsetMillis, events: events)

                if color != currentColor {
                    if currentSegment.count >= 2, let segmentColor = currentColor {
                        segments.append(RouteSegmentData(coordinates: currentSegment, color: segmentColor))
                    }
                    if let last = lastCoordinate {
                        currentSegment = [last, clCoord]
                    } else {
                        currentSegment = [clCoord]
                    }
                    currentColor = color
                } else {
                    currentSegment.append(clCoord)
                }
                lastCoordinate = clCoord
            }

            if currentSegment.count >= 2, let segmentColor = currentColor {
                segments.append(RouteSegmentData(coordinates: currentSegment, color: segmentColor))
            }

            return segments
        }

        private func colorForOffset(_ offset: TimeInterval, events: [DriveEvent]) -> UIColor {
            for event in events where event.type == .engage {
                if let endOffset = event.data.endRouteOffsetMillis {
                    if offset >= event.routeOffsetMillis && offset <= endOffset {
                        return UIColor(Color.engagedGreen)
                    }
                }
            }

            for event in events where event.type == .overriding {
                if let endOffset = event.data.endRouteOffsetMillis {
                    if offset >= event.routeOffsetMillis && offset <= endOffset {
                        return UIColor(Color.engagedGrey)
                    }
                }
            }

            return UIColor(Color.drivingBlue)
        }
    }
}

// MARK: - Supporting Types

private struct MapCameraAnchor {
    let coordinate: CLLocationCoordinate2D
    let heading: CLLocationDirection
}

private class CarAnnotation: NSObject, MKAnnotation {
    @objc dynamic var coordinate: CLLocationCoordinate2D
    
    init(coordinate: CLLocationCoordinate2D) {
        self.coordinate = coordinate
        super.init()
    }
}

private class MarkerAnnotation: NSObject, MKAnnotation {
    enum MarkerType {
        case start, end
    }
    
    let coordinate: CLLocationCoordinate2D
    let markerType: MarkerType
    
    init(coordinate: CLLocationCoordinate2D, markerType: MarkerType) {
        self.coordinate = coordinate
        self.markerType = markerType
        super.init()
    }
}

private class ColoredPolyline: MKPolyline {
    var color: UIColor = .green
}

private struct RouteSegmentData {
    let coordinates: [CLLocationCoordinate2D]
    let color: UIColor
}

// MARK: - SwiftUI Components

private struct MapControlButton: View {
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            if #available(iOS 26.0, *) {
                Image(systemName: systemImage)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
                    .glassEffect(.regular, in: Circle())
            } else {
                Image(systemName: systemImage)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
                    .background(.ultraThinMaterial, in: Circle())
            }
        }
        .buttonStyle(.plain)
        .shadow(radius: 4)
    }
}
