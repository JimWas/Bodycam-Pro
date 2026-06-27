import SwiftUI
import GoogleMobileAds
import UIKit
import AppTrackingTransparency

class AdMobManager: NSObject, ObservableObject {
    static let shared = AdMobManager()

    // Properties updated to native Swift naming
    private var interstitial: InterstitialAd?
    private var rewardedAd: RewardedAd?

    // Native ad support
    @Published var nativeAd: NativeAd?
    private var nativeAdLoader: AdLoader?

    // Track pending completion handler for rewarded ads
    private var rewardedAdCompletion: ((Bool) -> Void)?
    private var didEarnReward = false

    // Track whether user allowed tracking - used for all ad requests
    private var trackingAllowed = false

    // MARK: - Ad Unit IDs
    let interstitialID = "ca-app-pub-3057383894764696/7162334670"
    let rewardedID     = "ca-app-pub-3057383894764696/3121584402"
    let nativeAdID     = "ca-app-pub-3057383894764696/4017296581"

    override init() {
        super.init()
    }

    // MARK: - Helper to check premium status
    private var isPremium: Bool {
        UserDefaults.standard.bool(forKey: "isPremium")
    }

    // MARK: - Initialization
    func initializeAdMob(trackingStatus: ATTrackingManager.AuthorizationStatus) {
        // Skip initialization if premium
        if isPremium {
            print("AdMob: User is premium, skipping initialization")
            return
        }

        // Only allow tracking if user explicitly authorized it
        trackingAllowed = (trackingStatus == .authorized)

        // Configure AdMob to disable tracking features when user denied
        if !trackingAllowed {
            // Disable personalized ads and tracking when user opted out
            MobileAds.shared.requestConfiguration.tagForChildDirectedTreatment = true
        }

        // Modern SDK uses MobileAds.shared.start
        MobileAds.shared.start { status in
            print("AdMob SDK Initialized (tracking: \(self.trackingAllowed ? "enabled" : "disabled"))")
            self.loadInterstitial()
            self.loadRewardedAd()
            self.loadNativeAd()
        }
    }

    // Create ad request with proper tracking settings
    private func createAdRequest() -> Request {
        let request = Request()

        // If tracking is not allowed, request non-personalized ads only
        if !trackingAllowed {
            let extras = Extras()
            extras.additionalParameters = ["npa": "1"] // Non-personalized ads
            request.register(extras)
        }

        return request
    }

    // MARK: - Interstitial Logic
    func loadInterstitial() {
        if isPremium { return }
        let request = createAdRequest()
        InterstitialAd.load(with: interstitialID, request: request) { [weak self] ad, error in
            if let error = error {
                print("Failed to load interstitial: \(error.localizedDescription)")
                return
            }
            self?.interstitial = ad
            self?.interstitial?.fullScreenContentDelegate = self
        }
    }

    func showInterstitialAd() {
        if isPremium { return }
        guard let root = rootVC else { return }

        if let ad = interstitial {
            ad.present(from: root)
        } else {
            print("Interstitial ad wasn't ready.")
            loadInterstitial()
        }
    }

    // MARK: - Rewarded Logic
    func loadRewardedAd() {
        if isPremium { return }
        let request = createAdRequest()
        RewardedAd.load(with: rewardedID, request: request) { [weak self] ad, error in
            if let error = error {
                print("Failed to load rewarded ad: \(error.localizedDescription)")
                return
            }
            self?.rewardedAd = ad
            self?.rewardedAd?.fullScreenContentDelegate = self
        }
    }

    func showRewardedAd(completion: @escaping (Bool) -> Void) {
        if isPremium {
            completion(true) // Automatically grant reward if premium
            return
        }
        guard let root = rootVC else {
            completion(false)
            return
        }

        if let ad = rewardedAd {
            rewardedAdCompletion = completion
            didEarnReward = false

            ad.present(from: root) { [weak self] in
                print("User earned reward.")
                self?.didEarnReward = true
            }
        } else {
            print("Rewarded ad wasn't ready.")
            loadRewardedAd()
            completion(false)
        }
    }

    // MARK: - Native Ad Logic
    func loadNativeAd() {
        if isPremium { return }
        guard let root = rootVC else {
            // Retry after a short delay if root VC isn't available yet
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                self?.loadNativeAd()
            }
            return
        }

        let options = MultipleAdsAdLoaderOptions()
        options.numberOfAds = 1

        nativeAdLoader = AdLoader(
            adUnitID: nativeAdID,
            rootViewController: root,
            adTypes: [.native],
            options: [options]
        )
        nativeAdLoader?.delegate = self
        nativeAdLoader?.load(createAdRequest())
    }

    // MARK: - Helper to find the Root View Controller
    var rootVC: UIViewController? {
        guard let scene = UIApplication.shared.connectedScenes.first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene,
              let window = scene.windows.first(where: { $0.isKeyWindow }) else {
            return nil
        }
        return window.rootViewController
    }
}

// MARK: - Full Screen Content Delegate
extension AdMobManager: FullScreenContentDelegate {

    func adDidDismissFullScreenContent(_ ad: FullScreenPresentingAd) {
        if ad is InterstitialAd {
            loadInterstitial()
        } else if ad is RewardedAd {
            rewardedAdCompletion?(didEarnReward)
            rewardedAdCompletion = nil
            didEarnReward = false
            loadRewardedAd()
        }
    }

    func ad(_ ad: FullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: Error) {
        print("Ad failed to present: \(error.localizedDescription)")
        if ad is InterstitialAd {
            loadInterstitial()
        } else if ad is RewardedAd {
            rewardedAdCompletion?(false)
            rewardedAdCompletion = nil
            didEarnReward = false
            loadRewardedAd()
        }
    }
}

// MARK: - Native Ad Loader Delegate
extension AdMobManager: AdLoaderDelegate, NativeAdLoaderDelegate {

    func adLoader(_ adLoader: AdLoader, didReceive nativeAd: NativeAd) {
        print("Native ad loaded successfully")
        self.nativeAd = nativeAd
    }

    func adLoader(_ adLoader: AdLoader, didFailToReceiveAdWithError error: Error) {
        print("Native ad failed to load: \(error.localizedDescription)")
        // Retry after delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) { [weak self] in
            self?.loadNativeAd()
        }
    }
}
