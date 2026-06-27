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

        // Ad badge
        let adLabel = UILabel()
        adLabel.text = "Ad"
        adLabel.font = .systemFont(ofSize: 10, weight: .bold)
        adLabel.textColor = .white
        adLabel.backgroundColor = UIColor.systemOrange
        adLabel.textAlignment = .center
        adLabel.layer.cornerRadius = 4
        adLabel.clipsToBounds = true
        adLabel.translatesAutoresizingMaskIntoConstraints = false

        // Icon
        let iconView = UIImageView()
        iconView.contentMode = .scaleAspectFill
        iconView.clipsToBounds = true
        iconView.layer.cornerRadius = 8
        iconView.translatesAutoresizingMaskIntoConstraints = false

        // Headline
        let headlineLabel = UILabel()
        headlineLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        headlineLabel.textColor = .label
        headlineLabel.numberOfLines = 1
        headlineLabel.translatesAutoresizingMaskIntoConstraints = false

        // Body
        let bodyLabel = UILabel()
        bodyLabel.font = .systemFont(ofSize: 11)
        bodyLabel.textColor = .secondaryLabel
        bodyLabel.numberOfLines = 2
        bodyLabel.translatesAutoresizingMaskIntoConstraints = false

        // CTA
        let ctaButton = UIButton(type: .system)
        ctaButton.titleLabel?.font = .systemFont(ofSize: 12, weight: .bold)
        ctaButton.setTitleColor(.white, for: .normal)
        ctaButton.backgroundColor = UIColor.systemBlue
        ctaButton.layer.cornerRadius = 8
        ctaButton.isUserInteractionEnabled = false
        ctaButton.translatesAutoresizingMaskIntoConstraints = false

        // Media view — required so AdMob can render video ads
        let mediaView = MediaView()
        mediaView.contentMode = .scaleAspectFit
        mediaView.translatesAutoresizingMaskIntoConstraints = false

        adView.addSubview(adLabel)
        adView.addSubview(iconView)
        adView.addSubview(headlineLabel)
        adView.addSubview(bodyLabel)
        adView.addSubview(ctaButton)
        adView.addSubview(mediaView)

        adView.iconView = iconView
        adView.headlineView = headlineLabel
        adView.bodyView = bodyLabel
        adView.callToActionView = ctaButton
        adView.mediaView = mediaView

        NSLayoutConstraint.activate([
            // Ad badge — top-left
            adLabel.topAnchor.constraint(equalTo: adView.topAnchor, constant: 8),
            adLabel.leadingAnchor.constraint(equalTo: adView.leadingAnchor, constant: 10),
            adLabel.widthAnchor.constraint(equalToConstant: 24),
            adLabel.heightAnchor.constraint(equalToConstant: 16),

            // Icon — below ad badge
            iconView.topAnchor.constraint(equalTo: adLabel.bottomAnchor, constant: 6),
            iconView.leadingAnchor.constraint(equalTo: adView.leadingAnchor, constant: 10),
            iconView.widthAnchor.constraint(equalToConstant: 40),
            iconView.heightAnchor.constraint(equalToConstant: 40),

            // Headline — right of icon
            headlineLabel.topAnchor.constraint(equalTo: iconView.topAnchor),
            headlineLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 8),
            headlineLabel.trailingAnchor.constraint(equalTo: ctaButton.leadingAnchor, constant: -8),

            // Body — below headline
            bodyLabel.topAnchor.constraint(equalTo: headlineLabel.bottomAnchor, constant: 2),
            bodyLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 8),
            bodyLabel.trailingAnchor.constraint(equalTo: ctaButton.leadingAnchor, constant: -8),

            // CTA — right column, vertically centered with icon
            ctaButton.trailingAnchor.constraint(equalTo: adView.trailingAnchor, constant: -10),
            ctaButton.centerYAnchor.constraint(equalTo: iconView.centerYAnchor),
            ctaButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 76),
            ctaButton.heightAnchor.constraint(equalToConstant: 30),

            // Media view — full width below the text row, fills remaining height
            mediaView.topAnchor.constraint(equalTo: iconView.bottomAnchor, constant: 8),
            mediaView.leadingAnchor.constraint(equalTo: adView.leadingAnchor),
            mediaView.trailingAnchor.constraint(equalTo: adView.trailingAnchor),
            mediaView.bottomAnchor.constraint(equalTo: adView.bottomAnchor),
        ])

        return adView
    }

    func updateUIView(_ adView: NativeAdView, context: Context) {
        adView.nativeAd = nativeAd

        if let iconImage = nativeAd.icon?.image {
            (adView.iconView as? UIImageView)?.image = iconImage
        }

        (adView.headlineView as? UILabel)?.text = nativeAd.headline
        (adView.bodyView as? UILabel)?.text = nativeAd.body

        if let cta = nativeAd.callToAction {
            (adView.callToActionView as? UIButton)?.setTitle(cta, for: .normal)
            adView.callToActionView?.isHidden = false
        } else {
            adView.callToActionView?.isHidden = true
        }

        // Hide media view when no media content (image-only ads)
        adView.mediaView?.isHidden = nativeAd.mediaContent.hasVideoContent == false
    }
}
