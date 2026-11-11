import SwiftUI
import UIKit

/// Reuses the existing CoreBluetooth adapter. This panel never reads mock measurements.
struct PulseTrackerView: View {
    @EnvironmentObject private var tracker: DeviceModel
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(spacing: 13) {
                        Image(systemName: "sensor.tag.radiowaves.forward").font(.system(size: 36, weight: .light)).foregroundStyle(PulseColor.load)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(tracker.connectedName ?? "Connect your tracker").font(PulseFont.body(23).weight(.semibold))
                            Text(tracker.connectedName == nil ? "Bluetooth connection" : "Bluetooth link connected").font(PulseFont.body(12)).foregroundStyle(PulseColor.muted)
                        }
                    }
                    PulseCard {
                        Text(tracker.status).font(PulseFont.body(14)).fixedSize(horizontal: false, vertical: true).accessibilityLabel("Tracker status: " + tracker.status)
                    }
                    if tracker.connectedName != nil {
                        TimelineView(.periodic(from: .now, by: 1)) { timeline in
                            PulseCard {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("LIVE HEART RATE").font(PulseFont.label()).tracking(0.8)
                                    if let bpm = tracker.heartRate, let date = tracker.heartRateReceivedAt,
                                       (0...10).contains(timeline.date.timeIntervalSince(date)) {
                                        HStack(alignment: .firstTextBaseline, spacing: 5) {
                                            Text(bpm.formatted(.number.precision(.fractionLength(0)))).font(PulseFont.number(44)).monospacedDigit()
                                            Text("BPM").font(PulseFont.label(11)).foregroundStyle(PulseColor.muted)
                                        }.accessibilityElement(children: .combine).accessibilityLabel("Live heart rate, \(Int(bpm)) beats per minute")
                                        Text("Received from your connected tracker").font(PulseFont.body(11)).foregroundStyle(PulseColor.mint)
                                    } else {
                                        Text("Waiting for a fresh heart-rate sample").font(PulseFont.body(17).weight(.semibold))
                                        Text("A Bluetooth link alone does not confirm a live data stream.").font(PulseFont.body(12)).foregroundStyle(PulseColor.muted)
                                    }
                                }.frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        if tracker.canStartCustomStream || tracker.startingCustomStream {
                            Button(tracker.startingCustomStream ? "STARTING HEART RATE…" : "START DEVICE HEART RATE") { tracker.startCustomStream() }
                                .buttonStyle(PulseTrackerButton()).disabled(tracker.startingCustomStream)
                            Text("Experimental WHOOP connection request. Requires a matching device acknowledgement before requesting live heart rate; actual model and firmware compatibility remain unverified.")
                                .font(PulseFont.body(12)).foregroundStyle(PulseColor.muted)
                        }
                        Button("DISCONNECT") { tracker.disconnect() }.buttonStyle(PulseTrackerButton(secondary: true))
                    } else {
                        Button(tracker.isScanning ? "STOP SEARCHING" : "SEARCH FOR DEVICES") {
                            if tracker.isScanning { tracker.stop() } else { tracker.scan() }
                        }.buttonStyle(PulseTrackerButton())
                        if tracker.isScanning {
                            ProgressView("Searching nearby Bluetooth trackers…").font(PulseFont.body(12)).tint(PulseColor.load).frame(minHeight: 44)
                        }
                        if !tracker.devices.isEmpty {
                            Text("NEARBY DEVICES").font(PulseFont.label()).tracking(0.8)
                            ForEach(tracker.devices) { item in
                                Button { tracker.connect(item) } label: {
                                    PulseCard {
                                        HStack(spacing: 10) {
                                            Image(systemName: "sensor.tag.radiowaves.forward").foregroundStyle(PulseColor.sleep)
                                            VStack(alignment: .leading, spacing: 4) {
                                                Text(item.name).font(PulseFont.body(15).weight(.semibold))
                                                Text("\(item.rssi) dBm").font(PulseFont.body(11)).foregroundStyle(PulseColor.muted)
                                            }
                                            Spacer()
                                            Image(systemName: "chevron.right").font(.system(size: 11))
                                        }.frame(minHeight: 44)
                                    }
                                }.buttonStyle(.plain).accessibilityLabel("Connect to \(item.name), signal \(item.rssi) dBm")
                            }
                        } else if !tracker.isScanning {
                            PulseCard {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Ready when your tracker is").font(PulseFont.body(17).weight(.semibold))
                                    Text("Keep it nearby and enable heart-rate broadcasting if your device provides it. Bluetooth access is requested when you search.").font(PulseFont.body(13)).foregroundStyle(PulseColor.muted)
                                }
                            }
                        }
                    }
                    PulseCard {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("WHAT THIS CONNECTION CAN DO").font(PulseFont.label()).tracking(0.6)
                            Text("Listen for standard Bluetooth heart-rate broadcasts, or try the selected WHOOP service families already implemented. Individual WHOOP 4.0, 5.0 and MG compatibility has not been verified on physical devices.").font(PulseFont.body(12)).foregroundStyle(PulseColor.muted)
                            Text("Home scores remain sample data. This connection does not sync device history or calculate measured Recovery, Sleep Performance, daily Strain, ECG or blood pressure.").font(PulseFont.body(12)).foregroundStyle(PulseColor.muted)
                        }
                    }
                    Button("OPEN BLUETOOTH PERMISSIONS") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                    }.buttonStyle(PulseTrackerButton(secondary: true))
                }.padding(16).frame(maxWidth: 580).frame(maxWidth: .infinity)
            }.scrollIndicators(.hidden).background(PulseColor.background)
                .navigationTitle("Tracker").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() }.frame(minWidth: 44, minHeight: 44) } }
                .toolbarBackground(PulseColor.background, for: .navigationBar).toolbarBackground(.visible, for: .navigationBar)
        }.font(PulseFont.body()).foregroundStyle(PulseColor.text).tint(PulseColor.sleep).preferredColorScheme(.dark)
            .onDisappear { if tracker.isScanning { tracker.stop() } }
    }
}
private struct PulseTrackerButton: ButtonStyle {
    var secondary = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(PulseFont.label(11)).tracking(0.6).frame(maxWidth: .infinity, minHeight: 46)
            .foregroundStyle(secondary ? PulseColor.text : PulseColor.background)
            .background(secondary ? PulseColor.card : PulseColor.sleep, in: RoundedRectangle(cornerRadius: 9))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}
