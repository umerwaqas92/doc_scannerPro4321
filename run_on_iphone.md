# Run app on physical iPhone (when "Could not run" or "invalid signature" appears)

Error you may see: **"The executable contains an invalid signature" (0xe8008014)**  
The build succeeds but the app cannot be installed on the device. Follow these steps in order.

---

## Step 1: Trust the developer on your iPhone
- **Settings → General → VPN & Device Management**
- Tap your **Developer App** (your Apple ID / team name)
- Tap **Trust "[your name]"** and confirm

---

## Step 2: Clean and run from Xcode (most reliable)

In Terminal, from the project folder:

```bash
# Clean Flutter and iOS build
flutter clean && flutter pub get

# Open Xcode
open ios/Runner.xcworkspace
```

In Xcode:
1. Select your **iPhone** as the run target (top toolbar, next to "Runner").
2. **Product → Clean Build Folder** (⇧⌘K).
3. **Product → Run** (⌘R).

This uses Xcode’s signing and usually fixes the invalid signature. After it runs once from Xcode, `flutter run` may work for future runs.

---

## Step 3: If you still use `flutter run` and it fails

1. **Delete the app** from your iPhone (long-press app icon → Remove App).
2. Run again:
   ```bash
   flutter clean && flutter pub get && flutter run -d <your-iphone-id>
   ```
3. If it still says "invalid signature", use **Step 2** (run from Xcode) for now.
