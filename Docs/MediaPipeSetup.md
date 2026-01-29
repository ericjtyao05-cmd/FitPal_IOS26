# MediaPipe iOS Setup (FitPal)

This demo uses `MediaPipeTasksVision` (Pose Landmarker) for live camera pose detection.

## 1) Add CocoaPods (recommended by MediaPipe iOS docs)
Create a `Podfile` next to your `.xcodeproj`:

```
platform :ios, '16.0'
use_frameworks!

target 'FitPalApp' do
  pod 'MediaPipeTasksVision'
end
```

Then run:

```
pod install
```

Open the generated `.xcworkspace`.

## 2) Add the model file
Download `pose_landmarker.task` and add it to your app bundle resources.
For this SwiftPM demo, place it here:

`Sources/FitPalApp/Resources/Models/pose_landmarker.task`

## 3) Camera permissions
Add the following key to your app's `Info.plist`:

```
NSCameraUsageDescription
```

Example value: "FitPal needs camera access to analyze your lift."

## 4) Wire the live demo
The live camera path uses:

- `Sources/FitPalApp/Services/MediaPipePoseService.swift`
- `Sources/FitPalApp/Services/CameraService.swift`
- `Sources/FitPalApp/Views/LivePoseView.swift`

If you see `MediaPipeTasksVision not available`, CocoaPods is not linked to the target.
