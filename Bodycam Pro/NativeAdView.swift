import SwiftUI
import GoogleMobileAds

// MARK: - SwiftUI Native Ad View
struct NativeAdBannerView: View {
    @ObservedObject private var adManager = AdMobManager.shared

    private var isPremium: Bool {
        UserDefaults.standard.bool(forKey: "isPremium")
    }

    var body: some View {
        Group {
            if !isPremium, let nativeAd = adManager.nativeAd {
                NativeAdRepresentable(nativeAd: nativeAd)
                    .frame(height: 120)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
            }
        }
    }
}

// MARK: - UIViewRepresentable for GADNativeAdView
struct NativeAdRepresentable: UIViewRepresentable {
    let nativeAd: NativeAd

    func makeUIView(context: Context) -> NativeAdView {
        let adView = NativeAdView()
        adView.backgroundColor = .white
        adView.layer.cornerRadius = 12
        adView.clipsToBounds = true

        // Ad label
        let adLabel = UILabel()
        adLabel.text = "Ad"
        adLabel.font = .systemFont(ofSize: 10, weight: .bold)
        adLabel.textColor = .white
        adLabel.backgroundColor = UIColor.systemOrange
        adLabel.textAlignment = .center
        adLabel.layer.cornerRadius = 4
        adLabel.clipsToBounds = true
        adLabel.translatesAutoresizingMaskIntoConstraints = false

        // Icon image view
        let iconView = UIImageView()
        iconView.contentMode = .scaleAspectFill
        iconView.clipsToBounds = true
        iconView.layer.cornerRadius = 8
        iconView.translatesAutoresizingMaskIntoConstraints = false

        // Headline label
        let headlineLabel = UILabel()
        headlineLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        headlineLabel.textColor = .label
        headlineLabel.numberOfLines = 1
        headlineLabel.translatesAutoresizingMaskIntoConstraints = false

        // Body label
        let bodyLabel = UILabel()
        bodyLabel.font = .systemFont(ofSize: 12)
        bodyLabel.textColor = .secondaryLabel
        bodyLabel.numberOfLines = 2
        bodyLabel.translatesAutoresizingMaskIntoConstraints = false

        // Call to action button
        let ctaButton = UIButton(type: .system)
        ctaButton.titleLabel?.font = .systemFont(ofSize: 13, weight: .bold)
        ctaButton.setTitleColor(.white, for: .normal)
        ctaButton.backgroundColor = UIColor.systemBlue
        ctaButton.layer.cornerRadius = 8
        ctaButton.isUserInteractionEnabled = false // Let the ad view handle taps
        ctaButton.translatesAutoresizingMaskIntoConstraints = false

        // Add subviews
        adView.addSubview(adLabel)
        adView.addSubview(iconView)
        adView.addSubview(headlineLabel)
        adView.addSubview(bodyLabel)
        adView.addSubview(ctaButton)

        // Register views with the native ad view
        adView.iconView = iconView
        adView.headlineView = headlineLabel
        adView.bodyView = bodyLabel
        adView.callToActionView = ctaButton

        // Constraints
        NSLayoutConstraint.activate([
            // Ad label
            adLabel.topAnchor.constraint(equalTo: adView.topAnchor, constant: 8),
            adLabel.leadingAnchor.constraint(equalTo: adView.leadingAnchor, constant: 10),
            adLabel.widthAnchor.constraint(equalToConstant: 24),
            adLabel.heightAnchor.constraint(equalToConstant: 16),

            // Icon
            iconView.topAnchor.constraint(equalTo: adLabel.bottomAnchor, constant: 6),
            iconView.leadingAnchor.constraint(equalTo: adView.leadingAnchor, constant: 10),
            iconView.widthAnchor.constraint(equalToConstant: 48),
            iconView.heightAnchor.constraint(equalToConstant: 48),

            // Headline
            headlineLabel.topAnchor.constraint(equalTo: adLabel.bottomAnchor, constant: 6),
            headlineLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 10),
            headlineLabel.trailingAnchor.constraint(equalTo: ctaButton.leadingAnchor, constant: -8),

            // Body
            bodyLabel.topAnchor.constraint(equalTo: headlineLabel.bottomAnchor, constant: 2),
            bodyLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 10),
            bodyLabel.trailingAnchor.constraint(equalTo: ctaButton.leadingAnchor, constant: -8),

            // CTA Button
            ctaButton.trailingAnchor.constraint(equalTo: adView.trailingAnchor, constant: -10),
            ctaButton.centerYAnchor.constraint(equalTo: adView.centerYAnchor, constant: 4),
            ctaButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 80),
            ctaButton.heightAnchor.constraint(equalToConstant: 32),
        ])

        return adView
    }

    func updateUIView(_ adView: NativeAdView, context: Context) {
        adView.nativeAd = nativeAd

        // Update icon
        if let iconImage = nativeAd.icon?.image {
            (adView.iconView as? UIImageView)?.image = iconImage
        }

        // Update headline
        (adView.headlineView as? UILabel)?.text = nativeAd.headline

        // Update body
        (adView.bodyView as? UILabel)?.text = nativeAd.body

        // Update CTA
        if let cta = nativeAd.callToAction {
            (adView.callToActionView as? UIButton)?.setTitle(cta, for: .normal)
            adView.callToActionView?.isHidden = false
        } else {
            adView.callToActionView?.isHidden = true
        }
    }
}
