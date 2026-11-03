// Declared for real further down docs/sdks/ios/call-verification.md, and used
// by the sample above it.
import SwiftUI
import RelavoiSDK

struct BannerView: View {
    let result: VerificationResult
    var body: some View { Text(result.verified ? "Verified" : "Not verified") }
}
