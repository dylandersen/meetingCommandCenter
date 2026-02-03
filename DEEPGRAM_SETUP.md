# Deepgram API Configuration

The Meeting Command Center includes support for voice transcription using the Deepgram API. This is an **optional** feature - the component will work without it, but voice transcription will not be available.

## Files Included

The following Deepgram-related metadata files have been copied:

1. **Custom Metadata Type**: `Deepgram_API_Config__mdt`
   - Object definition: `objects/Deepgram_API_Config__mdt/Deepgram_API_Config__mdt.object-meta.xml`
   - Field definition: `objects/Deepgram_API_Config__mdt/fields/API_Key__c.field-meta.xml`
   - Sample record: `customMetadata/Deepgram_API_Config__mdt.Default.md-meta.xml`

2. **Remote Site Setting**: `Deepgram_API`
   - File: `remoteSiteSettings/Deepgram_API.remoteSite-meta.xml`
   - Allows Apex to make HTTP callouts to `https://api.deepgram.com`

3. **CSP Trusted Site**: `Deepgram_WebSocket`
   - File: `cspTrustedSites/Deepgram_WebSocket.cspTrustedSite-meta.xml`
   - Allows Lightning Web Components to connect to Deepgram WebSocket API

## Setup Instructions

### Step 1: Get Your Deepgram API Key

1. Sign up for a Deepgram account at https://www.deepgram.com/
2. Navigate to your API keys section
3. Create a new API key or copy an existing one

### Step 2: Update the Custom Metadata Record

The sample Custom Metadata record includes a placeholder API key:
```
REPLACE_ME_WITH_REAL_DEEPGRAM_API_KEY
```

**Option A: Update via Salesforce UI**
1. Deploy the metadata to your org
2. Navigate to Setup → Custom Metadata Types → Deepgram API Config
3. Click "Manage Deepgram API Config Records"
4. Edit the "Default" record
5. Replace the placeholder with your actual API key
6. Save

**Option B: Update the Metadata File**
1. Edit `force-app/main/default/customMetadata/Deepgram_API_Config__mdt.Default.md-meta.xml`
2. Replace `REPLACE_ME_WITH_REAL_DEEPGRAM_API_KEY` with your actual API key
3. Redeploy the Custom Metadata record

### Step 3: Deploy All Metadata

Deploy all Deepgram-related metadata:
```bash
sf project deploy start \
  --source-dir force-app/main/default/objects/Deepgram_API_Config__mdt \
  --source-dir force-app/main/default/customMetadata/Deepgram_API_Config__mdt \
  --source-dir force-app/main/default/remoteSiteSettings/Deepgram_API \
  --source-dir force-app/main/default/cspTrustedSites/Deepgram_WebSocket
```

Or deploy everything at once:
```bash
sf project deploy start --source-dir force-app
```

## Verification

After deployment, verify the configuration:

1. **Check Custom Metadata**: Setup → Custom Metadata Types → Deepgram API Config → Manage Records → Verify "Default" record has your API key
2. **Check Remote Site**: Setup → Remote Site Settings → Verify "Deepgram_API" is active
3. **Check CSP Trusted Site**: Setup → CSP Trusted Sites → Verify "Deepgram_WebSocket" is active

## Testing

To test voice transcription:
1. Navigate to Meeting Command Center
2. Click "Recap Meeting" on a past event
3. Click the microphone icon in the recap modal
4. Record audio and verify transcription appears

## Troubleshooting

**Error: "Deepgram API key not configured"**
- Verify the Custom Metadata record exists with Developer Name "Default"
- Verify the API_Key__c field contains a valid API key (not the placeholder)

**Error: "Deepgram API returned error: 401"**
- Your API key is invalid or expired
- Generate a new API key from Deepgram dashboard

**Error: "Callout failed" or "Site not found"**
- Verify Remote Site Setting "Deepgram_API" is deployed and active
- Check the URL matches: `https://api.deepgram.com`

**Voice recording button doesn't appear**
- Verify CSP Trusted Site "Deepgram_WebSocket" is deployed and active
- Check browser console for CSP errors

## Security Notes

⚠️ **Important**: Never commit real API keys to version control!

- The placeholder `REPLACE_ME_WITH_REAL_DEEPGRAM_API_KEY` is safe to commit
- Replace it with your real key only in your deployment org
- Consider using Protected Custom Metadata for production orgs
- Use different API keys for different environments (dev, staging, production)

