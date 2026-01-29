# FitPal

FitPal is an iOS app that analyzes lifting form from 2D pose data. It supports:

- Demo analysis using bundled samples
- Video upload with pose overlay rendering
- Live camera mode with real-time overlay, rep feedback, and annotated recording

## Requirements

- Xcode 16+ (tested on 26.2)
- iOS 16+
- CocoaPods

## Setup

```bash
pod install
```

Open `FitPalApp.xcworkspace` and run the app.

## Notes

- Live camera works best on a real device.
- The MediaPipe model file `pose_landmarker.task` must be present in the app bundle.

## License

MIT. See `LICENSE`.
