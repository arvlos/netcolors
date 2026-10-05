import CoreTelephony
import Network

/// Detects current carrier, network type, and VPN status.
struct CarrierInfo: Sendable {
    let carrierName: String
    let networkType: String  // WiFi, LTE, 5G, etc.
    let vpnActive: Bool
    let vpnName: String?

    static func current() async -> CarrierInfo {
        let (network, vpnActive) = await detectNetworkAndVPN()
        let carrier = detectCarrier(networkType: network)
        let vpnName = vpnActive ? detectVPNName() : nil
        return CarrierInfo(carrierName: carrier, networkType: network, vpnActive: vpnActive, vpnName: vpnName)
    }

    private static func detectCarrier(networkType: String) -> String {
        let networkInfo = CTTelephonyNetworkInfo()

        // Try serviceSubscriberCellularProviders (deprecated but may still work)
        if let providers = networkInfo.serviceSubscriberCellularProviders {
            for (_, carrier) in providers {
                if let name = carrier.carrierName,
                   !name.isEmpty, name != "--" {
                    return name
                }
            }
        }

        // Fallback: if on cellular, indicate that
        if networkType != "WiFi" && networkType != "None" && networkType != "Ethernet" {
            return "Cellular"
        }

        return networkType == "WiFi" ? "WiFi" : "Unknown"
    }

    private static func detectNetworkAndVPN() async -> (networkType: String, vpnActive: Bool) {
        await withCheckedContinuation { continuation in
            let monitor = NWPathMonitor()
            monitor.pathUpdateHandler = { path in
                monitor.cancel()

                // VPN detection: check for non-physical interface types
                let vpn = path.usesInterfaceType(.other)

                let networkType: String
                if path.usesInterfaceType(.wifi) {
                    networkType = "WiFi"
                } else if path.usesInterfaceType(.cellular) {
                    let networkInfo = CTTelephonyNetworkInfo()
                    if let radioTech = networkInfo.serviceCurrentRadioAccessTechnology?.values.first {
                        networkType = switch radioTech {
                        case CTRadioAccessTechnologyLTE: "LTE"
                        case CTRadioAccessTechnologyNR, CTRadioAccessTechnologyNRNSA: "5G"
                        case CTRadioAccessTechnologyHSDPA, CTRadioAccessTechnologyHSUPA: "3G"
                        case CTRadioAccessTechnologyEdge: "EDGE"
                        case CTRadioAccessTechnologyGPRS: "GPRS"
                        default: "Cellular"
                        }
                    } else {
                        networkType = "Cellular"
                    }
                } else if path.usesInterfaceType(.wiredEthernet) {
                    networkType = "Ethernet"
                } else {
                    networkType = "None"
                }

                continuation.resume(returning: (networkType, vpn))
            }
            monitor.start(queue: DispatchQueue.global(qos: .utility))
        }
    }

    /// Attempts to read the VPN configuration name from system network settings.
    private static func detectVPNName() -> String? {
        // Read VPN interface name from system configuration
        guard let cfDict = CFNetworkCopySystemProxySettings()?.takeRetainedValue() as? [String: Any],
              let scoped = cfDict["__SCOPED__"] as? [String: Any] else {
            return nil
        }

        // Look for utun/ipsec/ppp interfaces (typical VPN tunnels)
        for key in scoped.keys {
            if key.hasPrefix("utun") || key.hasPrefix("ipsec") || key.hasPrefix("ppp") {
                return key
            }
        }
        return nil
    }
}
