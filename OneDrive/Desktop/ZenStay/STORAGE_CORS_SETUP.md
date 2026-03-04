# Fix property images not showing on the booking page (Flutter web)

If property photos show as broken on the **booking page** in the browser, Firebase Storage is likely blocking the request due to **CORS**. Configure CORS on your Storage bucket using one of the methods below.

---

## Option A: Use Google Cloud Shell (no install, recommended)

You don’t need to install anything on your PC. Do everything in the browser.

1. **Open Google Cloud Console**  
   Go to: https://console.cloud.google.com/

2. **Select your project**  
   Use the project dropdown at the top and choose **zenstay-b3dc4** (or your Firebase project).

3. **Open Cloud Shell**  
   Click the **>_** (Activate Cloud Shell) icon at the top right. A terminal opens at the bottom of the page.

4. **Create the CORS config file** in Cloud Shell:
   ```bash
   cat > cors.json << 'EOF'
   [
     {
       "origin": ["*"],
       "method": ["GET", "HEAD", "OPTIONS"],
       "responseHeader": ["Content-Type", "Access-Control-Allow-Origin"],
       "maxAgeSeconds": 3600
     }
   ]
   EOF
   ```

5. **Apply CORS** to your Storage bucket:
   ```bash
   gsutil cors set cors.json gs://zenstay-b3dc4.appspot.com
   ```

6. **Hard-refresh** the booking page in your app (Ctrl+Shift+R). Images should load.

---

## Option B: Install Google Cloud SDK on Windows (then use gsutil locally)

If you prefer to run `gsutil` from your own machine:

1. **Download and install** the Google Cloud CLI for Windows:  
   https://cloud.google.com/sdk/docs/install  
   Or run this in PowerShell to download and run the installer:
   ```powershell
   (New-Object Net.WebClient).DownloadFile("https://dl.google.com/dl/cloudsdk/channels/rapid/GoogleCloudSDKInstaller.exe", "$env:Temp\GoogleCloudSDKInstaller.exe")
   & $env:Temp\GoogleCloudSDKInstaller.exe
   ```

2. **Restart PowerShell** (or your terminal) after installation so `gsutil` is on your PATH.

3. **Log in and set project:**
   ```bash
   gcloud auth login
   gcloud config set project zenstay-b3dc4
   ```

4. **Apply CORS** from your project folder (where `storage_cors.json` is):
   ```bash
   cd C:\Users\guerz\OneDrive\Desktop\ZenStay
   gsutil cors set storage_cors.json gs://zenstay-b3dc4.appspot.com
   ```

5. **Hard-refresh** the booking page (Ctrl+Shift+R).

---

## After CORS is set

- If your bucket name is different (e.g. another Firebase project), use that bucket in the command:  
  `gsutil cors set cors.json gs://YOUR-BUCKET-NAME.appspot.com`
- For production, restrict `"origin": ["*"]` to your real domain(s), e.g.  
  `["https://yourdomain.com", "https://www.yourdomain.com"]`.
