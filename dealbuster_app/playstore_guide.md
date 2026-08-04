# Google Play Store Publishing Guide – Dealbuster App

This guide will walk you through the process of building your signed release Android App Bundle (`.aab`) and uploading it to the Google Play Console for publication.

---

## Part 1: Prerequisites & Environment Setup

If you don't have Flutter set up on your machine yet, perform the following steps:

1. **Download the Flutter SDK**:
   * Visit [flutter.dev/docs/get-started/install/windows](https://docs.flutter.dev/get-started/install/windows) and download the latest stable Flutter SDK.
   * Extract the ZIP to `C:\flutter` (avoid paths with spaces like `C:\Program Files`).
2. **Configure Environment Variables**:
   * Open the Windows Start search, type **Environment Variables**, and select **Edit the system environment variables**.
   * Under System variables, edit the **Path** entry and add `C:\flutter\bin`.
   * Click **OK** to save.
3. **Install Android Studio**:
   * Download and install [Android Studio](https://developer.android.com/studio).
   * Open Android Studio, go to **Tools > SDK Manager**, and under the **SDK Tools** tab, check **Android SDK Command-line Tools (latest)** and click **Apply** to install.
4. **Agree to Licenses**:
   * Open PowerShell and run:
     ```powershell
     flutter doctor --android-licenses
     ```
   * Press `y` to accept all licenses.
5. **Verify Setup**:
   * Run `flutter doctor` to ensure Flutter, Java, and Android Toolchains are correctly configured.

---

## Part 2: Generate a Release Keystore

The keystore is a secure container that holds the cryptographic key used to digitally sign your app. Google Play requires every app bundle to be signed before submission.

1. Open PowerShell and navigate to the project directory or run the following command directly:
   ```powershell
   keytool -genkey -v -keystore c:\Users\blaaz\OneDrive\Desktop\Dealbuster\dealbuster_app\android\app\upload-keystore.jks -storetype PKCS12 -keyalg RSA -keysize 2048 -validity 10000 -alias upload
   ```
2. Enter a secure password (make note of this password!).
3. Answer the organizational prompts (name, country, etc.) and confirm with `yes`.
4. This generates the `upload-keystore.jks` file directly in your `android/app/` folder.

> [!WARNING]
> Keep your Keystore file and password safe! If you lose it, you will not be able to push updates/upgrades to the Play Store for your app.

---

## Part 3: Configure Signing in build.gradle

To automatically sign your build when generating the app bundle, configure the keystore parameters:

1. Create a file named `key.properties` in `android/` with the following values:
   ```properties
   storePassword=<YOUR_KEYSTORE_PASSWORD>
   keyPassword=<YOUR_KEY_PASSWORD_USUALLY_SAME>
   keyAlias=upload
   storeFile=upload-keystore.jks
   ```
2. Update the `buildTypes` section inside [android/app/build.gradle](file:///c:/Users/blaaz/OneDrive/Desktop/Dealbuster/dealbuster_app/android/app/build.gradle) to fetch the key info. 
   Here is the standard signature configuration pattern to place in `android/app/build.gradle`:
   ```groovy
   def keystoreProperties = new Properties()
   def keystorePropertiesFile = rootProject.file('key.properties')
   if (keystorePropertiesFile.exists()) {
       keystoreProperties.load(new FileInputStream(keystorePropertiesFile))
   }

   android {
       ...
       signingConfigs {
           release {
               keyAlias keystoreProperties['keyAlias']
               keyPassword keystoreProperties['keyPassword']
               storeFile keystoreProperties['storeFile'] ? file(keystoreProperties['storeFile']) : null
               storePassword keystoreProperties['storePassword']
           }
       }
       buildTypes {
           release {
               signingConfig signingConfigs.release
           }
       }
   }
   ```

---

## Part 4: Build the Release App Bundle

1. Open your terminal in the `dealbuster_app/` folder:
   ```powershell
   cd c:\Users\blaaz\OneDrive\Desktop\Dealbuster\dealbuster_app
   ```
2. Fetch package dependencies:
   ```powershell
   flutter pub get
   ```
3. Compile the production App Bundle:
   ```powershell
   flutter build appbundle --release
   ```
4. Once completed, your signed `.aab` file will be generated at:
   `[Project]/build/app/outputs/bundle/release/app-release.aab`

---

## Part 5: Google Play Console Submission

### 1. Developer Account Registration
* Go to the [Google Play Console](https://play.google.com/console).
* Register for a Google Developer Account (requires a one-time registration fee of $25 USD).

### 2. Create the Application
* Click **Create App** in the top right.
* Fill out the app metadata:
  * **App Name**: Dealbuster
  * **Default Language**: English (United States) / English (India)
  * **App or Game**: App
  * **Free or Paid**: Free
  * Check the declarations and click **Create App**.

### 3. Complete App Setup Tasks
Under the **Dashboard**, scroll to the **Set up your app** section. Complete each required questionnaire:
* **Privacy Policy URL**: Link to your [privacy.html](file:///c:/Users/blaaz/OneDrive/Desktop/Dealbuster/privacy.html) (e.g. `https://dealbuster.in/privacy.html`).
* **App Access**: Set to "All functionality is available without special access".
* **Ads**: Set to "No, my app does not contain ads" (or Yes if displaying external banners).
* **Content Rating**: Complete the questionnaire. Select "Utility/Communication/Other" and declare no violence or offensive materials.
* **Target Audience**: Select ages 18 and older.
* **News Apps**: Set to "No".
* **COVID-19 Contact Tracing**: Set to "My app is not a publicly available contact tracing or status app".
* **Data Safety**: Declare that your app fetches data but does not collect or share user personal data (no logins, no user profiles).
* **Government Apps**: Set to "No".
* **Financial Features**: Set to "My app doesn't provide any financial features".

### 4. Setup Store Listing
Go to **Grow > Main Store Listing** on the left menu:
* **Short Description**: Handpicked best deals, discounts, and real savings in India daily.
* **Full Description**: Re-use your [index.html](file:///c:/Users/blaaz/OneDrive/Desktop/Dealbuster/index.html) canonical metadata:
  > Dealbuster handpicks the best online shopping deals in India daily — electronics, fashion, beauty, home & health. No fake discounts, no inflated MRPs. Just real savings. Updated multiple times a day to capture flash loot deals before they expire.
* **Graphics**:
  * **App Icon**: 512 × 512 pixels PNG (use your logo badge).
  * **Feature Graphic**: 1024 × 500 pixels PNG.
  * **Phone Screenshots**: Upload at least 2 to 4 screenshots of your Flutter app showing the homepage and details screen views.

---

## Part 6: Submitting for Review (Play Store Policy Note)

> [!IMPORTANT]
> **New Policy for Personal Developer Accounts (Created after November 2023):**
> Google Play requires personal developer accounts to run a **Closed Testing Track** with at least **20 testers** opted-in continuously for at least **14 days** before you can publish to the public Production track.

### Running Closed Testing
1. In the console menu, go to **Release > Testing > Closed testing**.
2. Click **Create Track** (name it "Alpha Testing").
3. Create a release under this track and upload your `app-release.aab` bundle.
4. Under the **Testers** tab:
   * Create an email list of 20+ friends, family, or online testers.
   * Share the opt-in URL link provided in the console with them.
5. Once 20 testers have joined and installed the app on their devices, let the test run for **14 consecutive days**.
6. After 14 days, you can apply for **Production Access** directly on your Play Console dashboard. Google will review the application and grant access to publish the app publicly to the store!
