import Foundation
import Combine
@preconcurrency import CoreBluetooth
import WHOOPCore

struct NearbyDevice: Identifiable {
    let id: UUID
    let name: String
    let rssi: Int
}

/// Main-queue Bluetooth client. Only the opt-in verified Hello/HR request pair is encoded.
/// No firmware operations, history commands or private-server calls are implemented.
@MainActor
final class DeviceModel: NSObject, ObservableObject, @preconcurrency CBCentralManagerDelegate, @preconcurrency CBPeripheralDelegate {
    @Published private(set) var devices: [NearbyDevice] = []
    @Published private(set) var status = "Find a nearby sensor to see live heart rate."
    @Published private(set) var heartRate: Double?
    @Published private(set) var heartRateReceivedAt: Date?
    @Published private(set) var isScanning = false
    @Published private(set) var connectedName: String?
    @Published private(set) var validFrames = 0
    @Published private(set) var historicalFrames = 0
    @Published private(set) var lastHistoryRecord: WhoopHistoryRecord?
    @Published private(set) var canStartCustomStream = false
    @Published private(set) var startingCustomStream = false
    private var customSession: WhoopLiveSession?
    private var customCommandCharacteristic: CBCharacteristic?
    private var requiredNotifications: Set<CBUUID> = []
    private var readyNotifications: Set<CBUUID> = []
    private var requestTimeoutToken = UUID()
    private var heartRateToken = UUID()
    private var customDecoders: [CBUUID: WhoopFrameDecoder] = [:]
    private lazy var central = CBCentralManager(delegate: self, queue: .main)
    private var discovered: [UUID: CBPeripheral] = [:]
    private var active: CBPeripheral?
    var isConnecting: Bool { active != nil && connectedName == nil }
    private var pendingScan = false
    private var pendingReconnectID: UUID?
    private var scanToken = UUID()
    private var connectionToken = UUID()
    private let heartService = CBUUID(string: "180D")
    private let heartMeasurement = CBUUID(string: "2A37")
    private var scanServices: [CBUUID] {
        [heartService,
         CBUUID(string: "61080001-8D6D-82B8-614A-1C8CB0F8DCC6"),
         CBUUID(string: "FD4B0001-CCE1-4033-93CE-002D5875F58A")]
    }

    /// Only restores a sensor this app previously connected to; never scans automatically.
    func reconnectSavedDevice() {
        guard active == nil, !pendingScan,
              let saved = UserDefaults.standard.string(forKey: "whoop.tracker.identifier"),
              let identifier = UUID(uuidString: saved) else { return }
        pendingReconnectID = identifier
        if central.state == .poweredOn { reconnectPendingDevice() }
    }
    private func reconnectPendingDevice() {
        guard let identifier = pendingReconnectID else { return }
        pendingReconnectID = nil
        guard let peripheral = central.retrievePeripherals(withIdentifiers: [identifier]).first else {
            status = "Search again to reconnect your tracker."; return
        }
        discovered[identifier] = peripheral
        connect(NearbyDevice(id: identifier, name: peripheral.name ?? "Your tracker", rssi: 0))
    }

    func scan() {
        guard !isConnecting else { return }
        pendingReconnectID = nil
        pendingScan = true
        switch central.state {
        case .poweredOn: startScan()
        case .poweredOff: status = "Turn on Bluetooth to find your device."
        case .unauthorized: status = "Allow Bluetooth access in Settings to find your device."
        case .unsupported: pendingScan = false; status = "Bluetooth sensors aren’t supported on this device."
        default: status = "Preparing Bluetooth…"
        }
    }
    func stop() {
        // Do not initialize CoreBluetooth (or prompt for access) just to leave a screen.
        guard pendingScan || isScanning else { return }
        pendingScan = false
        scanToken = UUID()
        central.stopScan()
        isScanning = false
        if active == nil { status = devices.isEmpty ? "No sensors found. Keep your sensor nearby and try again." : "Choose a sensor below." }
    }
    private func startScan() {
        devices = []
        discovered = [:]
        isScanning = true
        status = "Looking for nearby sensors…"
        let token = UUID(); scanToken = token
        central.scanForPeripherals(withServices: scanServices, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        DispatchQueue.main.asyncAfter(deadline: .now() + 15) { [weak self] in
            guard let self, self.scanToken == token else { return }
            self.stop()
        }
    }
    func connect(_ device: NearbyDevice) {
        guard central.state == .poweredOn, let peripheral = discovered[device.id] else {
            status = "Scan again to find this sensor."; return
        }
        stop()
        if let previous = active, previous.identifier != peripheral.identifier { central.cancelPeripheralConnection(previous) }
        active = peripheral
        heartRate = nil; heartRateReceivedAt = nil; connectedName = nil; validFrames = 0; historicalFrames = 0; lastHistoryRecord = nil; resetCustomState()
        peripheral.delegate = self
        status = "Connecting to \(device.name)…"
        let token = UUID(); connectionToken = token
        central.connect(peripheral)
        DispatchQueue.main.asyncAfter(deadline: .now() + 20) { [weak self] in
            guard let self, self.connectionToken == token, self.connectedName == nil, self.active != nil else { return }
            self.disconnect()
            self.status = "Connection timed out. Keep the sensor nearby and try again."
        }
    }
    func disconnect() {
        pendingReconnectID = nil
        connectionToken = UUID()
        if let active { central.cancelPeripheralConnection(active) }
        active = nil; connectedName = nil; heartRate = nil; heartRateReceivedAt = nil; resetCustomState()
        status = "Disconnected."
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            if pendingScan { startScan() }
            else { reconnectPendingDevice() }
        case .poweredOff:
            isScanning = false; heartRate = nil; heartRateReceivedAt = nil; connectedName = nil; active = nil; resetCustomState()
            status = "Bluetooth is off. Turn it on to connect a sensor."
        case .unauthorized:
            isScanning = false; heartRate = nil; heartRateReceivedAt = nil; connectedName = nil; active = nil; resetCustomState()
            status = "Bluetooth access is off. Allow access in Settings."
        case .unsupported:
            isScanning = false; pendingScan = false; status = "Bluetooth sensors aren’t supported on this device."
        case .resetting: isScanning = false; status = "Bluetooth is restarting. Please try again."
        case .unknown: status = "Preparing Bluetooth…"
        @unknown default: status = "Bluetooth is unavailable."
        }
    }
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let name = (advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? peripheral.name ?? "Heart-rate sensor"
        discovered[peripheral.identifier] = peripheral
        devices.removeAll { $0.id == peripheral.identifier }
        devices.append(NearbyDevice(id: peripheral.identifier, name: name, rssi: RSSI.intValue))
        devices.sort { $0.rssi > $1.rssi }
    }
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        guard active?.identifier == peripheral.identifier else { return }
        connectionToken = UUID()
        connectedName = peripheral.name ?? "Sensor"
        UserDefaults.standard.set(peripheral.identifier.uuidString, forKey: "whoop.tracker.identifier")
        status = "Connected. Checking for heart-rate broadcast…"
        peripheral.discoverServices(scanServices)
    }
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        guard active?.identifier == peripheral.identifier else { return }
        connectionToken = UUID(); active = nil; connectedName = nil; heartRate = nil; heartRateReceivedAt = nil; resetCustomState()
        status = "Couldn’t connect. \(error?.localizedDescription ?? "Keep the sensor nearby and try again.")"
    }
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        guard active?.identifier == peripheral.identifier else { return }
        active = nil; connectedName = nil; heartRate = nil; heartRateReceivedAt = nil; resetCustomState()
        status = error == nil ? "Disconnected." : "Connection lost. Scan again to reconnect."
    }
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard active?.identifier == peripheral.identifier else { return }
        if let error { status = "Couldn’t read sensor services: \(error.localizedDescription)"; return }
        var found = false
        for service in peripheral.services ?? [] {
            if service.uuid == heartService {
                peripheral.discoverCharacteristics([heartMeasurement], for: service); found = true
            } else if let family = customFamily(service.uuid) {
                let ids = [2, 3, 4, 5].map { customCharacteristic($0, family: family) }
                peripheral.discoverCharacteristics(ids, for: service); found = true
            }
        }
        if !found { status = "Connected. No supported heart-rate service is available." }
    }
    private func customFamily(_ service: CBUUID) -> String? {
        if service == CBUUID(string: "61080001-8D6D-82B8-614A-1C8CB0F8DCC6") { return "6108" }
        if service == CBUUID(string: "FD4B0001-CCE1-4033-93CE-002D5875F58A") { return "FD4B" }
        return nil
    }
    private func customCharacteristic(_ number: Int, family: String) -> CBUUID {
        let suffix = family == "6108" ? "8D6D-82B8-614A-1C8CB0F8DCC6" : "CCE1-4033-93CE-002D5875F58A"
        return CBUUID(string: String(format: "%@%04X-%@", family, number, suffix))
    }
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard active?.identifier == peripheral.identifier else { return }
        if let error { status = "Couldn’t read heart rate: \(error.localizedDescription)"; return }
        if let family = customFamily(service.uuid) {
            let generation: WhoopGeneration = family == "6108" ? .gen4 : .maverick
            if let current = customSession, current.generation != generation { return }
            if customSession == nil { customSession = WhoopLiveSession(generation: generation) }
            customCommandCharacteristic = service.characteristics?.first {
                $0.uuid == customCharacteristic(2, family: family) &&
                ($0.properties.contains(.write) || $0.properties.contains(.writeWithoutResponse))
            }
            requiredNotifications = Set([3, 4, 5].map { customCharacteristic($0, family: family) })
            var listening = 0
            for item in service.characteristics ?? [] {
                if [3, 4, 5].map({ customCharacteristic($0, family: family) }).contains(item.uuid),
                   item.properties.contains(.notify) || item.properties.contains(.indicate) {
                    // GOOSE's framing constants are independently proven equal to MAVERICK;
                    // this selects a wire layout, not an inferred device model identity.
                    customDecoders[item.uuid] = WhoopFrameDecoder(generation: family == "6108" ? .gen4 : .maverick)
                    peripheral.setNotifyValue(true, for: item); listening += 1
                }
            }
            status = listening > 0 ? "Listening for WHOOP device data…" : "Connected, but device notifications are unavailable."
            updateCustomAvailability()
            return
        }
        guard let characteristic = service.characteristics?.first(where: { $0.uuid == heartMeasurement }) else {
            status = "No heart-rate broadcast found on this sensor."; return
        }
        if characteristic.properties.contains(.notify) || characteristic.properties.contains(.indicate) {
            peripheral.setNotifyValue(true, for: characteristic)
        } else if characteristic.properties.contains(.read) {
            peripheral.readValue(for: characteristic)
        } else { status = "This sensor isn’t sharing heart rate." }
    }
    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        guard active?.identifier == peripheral.identifier else { return }
        if customDecoders[characteristic.uuid] != nil {
            if error == nil && characteristic.isNotifying { readyNotifications.insert(characteristic.uuid) }
            else {
                readyNotifications.remove(characteristic.uuid)
                if customSession?.isWaiting == true {
                    customSession?.transportFailed(); requestTimeoutToken = UUID()
                }
            }
            updateCustomAvailability()
            status = error == nil ? "Listening for WHOOP device data. You can request live heart rate below." : "Device sharing couldn’t start: \(error!.localizedDescription)"
            return
        }
        guard characteristic.uuid == heartMeasurement else { return }
        if let error { status = "Heart-rate sharing couldn’t start: \(error.localizedDescription)" }
        else { status = characteristic.isNotifying ? "Waiting for live heart rate…" : "Heart-rate broadcast stopped." }
    }
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard active?.identifier == peripheral.identifier else { return }
        if var decoder = customDecoders[characteristic.uuid] {
            guard error == nil, let data = characteristic.value else { return }
            let frames = decoder.append(data)
            customDecoders[characteristic.uuid] = decoder
            validFrames += frames.count
            for frame in frames {
                if let history = WhoopHistoryRecord(frame: frame) {
                    historicalFrames += 1; lastHistoryRecord = history
                }
                handleCustomFrame(frame)
                if let bpm = frame.realtimeHeartRate { publishHeartRate(bpm); status = "Receiving WHOOP live heart rate." }
            }
            return
        }
        guard characteristic.uuid == heartMeasurement else { return }
        if let error { status = "Couldn’t read heart rate: \(error.localizedDescription)"; return }
        guard let data = characteristic.value, let bpm = HeartRateMeasurement.decode(data) else {
            status = "Waiting for a valid heart-rate reading…"; return
        }
        publishHeartRate(bpm)
        status = "Heart rate received."
    }

    private func publishHeartRate(_ bpm: Double) {
        heartRate = bpm
        heartRateReceivedAt = Date()
        let token = UUID(); heartRateToken = token
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
            guard let self, self.heartRateToken == token, self.active != nil else { return }
            self.heartRate = nil; self.heartRateReceivedAt = nil
            self.status = "No recent heart-rate signal. Check your sensor connection."
        }
    }

    /// User action only: a successful matching Hello ack must precede enabling HR.
    func startCustomStream() {
        guard canStartCustomStream, var session = customSession else { return }
        do {
            let bytes = try session.begin()
            customSession = session
            updateCustomAvailability()
            status = "Requesting a device connection check…"
            if writeCustom(bytes) { scheduleRequestTimeout() }
        } catch { status = "A device request is already in progress." }
    }
    private func writeCustom(_ bytes: Data) -> Bool {
        guard let peripheral = active, let characteristic = customCommandCharacteristic else {
            customSession?.transportFailed(); updateCustomAvailability(); return false
        }
        let type: CBCharacteristicWriteType
        if characteristic.properties.contains(.write) { type = .withResponse }
        else if characteristic.properties.contains(.writeWithoutResponse), peripheral.canSendWriteWithoutResponse { type = .withoutResponse }
        else {
            customSession?.transportFailed(); updateCustomAvailability()
            status = "The device isn’t ready for this request. Try again shortly."; return false
        }
        peripheral.writeValue(bytes, for: characteristic, type: type)
        return true
    }
    private func handleCustomFrame(_ frame: WhoopFrame) {
        guard var session = customSession else { return }
        let previous = session.state
        do {
            let next = try session.receive(frame)
            customSession = session
            updateCustomAvailability()
            if let next {
                status = "Device check accepted. Requesting live heart rate…"
                if writeCustom(next) { scheduleRequestTimeout() }
            } else if session.state != previous {
                requestTimeoutToken = UUID()
                switch session.state {
                case .streaming: status = "The device accepted live heart rate. Waiting for readings…"
                case .failed(.unsupported): status = "This device doesn’t support the request. Try heart-rate broadcasting instead."
                case .failed: status = "The device declined the request. No further initialization commands were sent."
                default: break
                }
            }
        } catch {
            customSession?.transportFailed(); updateCustomAvailability()
            status = "The live heart-rate request couldn’t be prepared."
        }
    }
    private func scheduleRequestTimeout() {
        let token = UUID(); requestTimeoutToken = token
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
            guard let self, self.requestTimeoutToken == token, self.customSession?.isWaiting == true else { return }
            self.customSession?.expire(); self.updateCustomAvailability()
            self.status = "The device did not confirm the request. Try reconnecting or heart-rate broadcasting."
        }
    }
    private func updateCustomAvailability() {
        startingCustomStream = customSession?.isWaiting ?? false
        canStartCustomStream = connectedName != nil && customCommandCharacteristic != nil &&
            requiredNotifications.count == 3 && requiredNotifications.isSubset(of: readyNotifications) &&
            (customSession?.canBegin ?? false)
    }
    private func resetCustomState() {
        customDecoders = [:]; customSession = nil; customCommandCharacteristic = nil; heartRateToken = UUID()
        requiredNotifications = []; readyNotifications = []; requestTimeoutToken = UUID()
        startingCustomStream = false; canStartCustomStream = false
    }
    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        guard active?.identifier == peripheral.identifier,
              characteristic.uuid == customCommandCharacteristic?.uuid, let error else { return }
        requestTimeoutToken = UUID(); customSession?.transportFailed(); updateCustomAvailability()
        status = "The device request could not be written: \(error.localizedDescription)"
    }

}
