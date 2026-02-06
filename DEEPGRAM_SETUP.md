# Tavily and Deepgram API Configuration

The Meeting Command Center requires API keys for both **Tavily** (competitive intelligence) and **Deepgram** (voice transcription). Both services offer free API keys that you can obtain quickly.

## Overview

- **Tavily API**: Powers the competitive intelligence feature in meeting preparation, providing company research and insights
- **Deepgram API**: Enables voice transcription for meeting recaps

Both APIs offer free tiers that are sufficient for testing and development. Follow the setup instructions below to get your free API keys.

## Files Included

### Tavily API Configuration

1. **Custom Metadata Type**: `Tavily_API_Config__mdt`
   - Object definition: `objects/Tavily_API_Config__mdt/Tavily_API_Config__mdt.object-meta.xml`
   - Field definition: `objects/Tavily_API_Config__mdt/fields/API_Key__c.field-meta.xml`
   - Sample record: `customMetadata/Tavily_API_Config__mdt.Default.md-meta.xml`

2. **Remote Site Setting**: `Tavily_API`
   - File: `remoteSiteSettings/Tavily_API.remoteSite-meta.xml`
   - Allows Apex to make HTTP callouts to `https://api.tavily.com`

### Deepgram API Configuration

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

### Step 1: Get Your Tavily API Key (FREE)

1. Visit https://tavily.com/
2. Sign up for a free account (no credit card required)
3. Navigate to your API keys section in the dashboard
4. Copy your API key (starts with `tvly-dev-`)

**Free Tier**: Tavily offers generous free credits for development and testing.

### Step 2: Get Your Deepgram API Key (FREE)

1. Visit https://www.deepgram.com/
2. Sign up for a free account (no credit card required)
3. Navigate to your API keys section in the dashboard
4. Create a new API key or copy an existing one

**Free Tier**: Deepgram offers free credits for testing voice transcription.

### Step 3: Update Custom Metadata Records

Both Custom Metadata records include placeholder API keys that need to be replaced.

#### Option A: Update via Salesforce UI (Recommended)

**For Tavily:**
1. Deploy the metadata to your org
2. Navigate to Setup → Custom Metadata Types → Tavily API Config
3. Click "Manage Tavily API Config Records"
4. Edit the "Default" record
5. Replace `REPLACE_ME_WITH_REAL_TAVILY_API_KEY` with your actual Tavily API key
6. Save

**For Deepgram:**
1. Navigate to Setup → Custom Metadata Types → Deepgram API Config
2. Click "Manage Deepgram API Config Records"
3. Edit the "Default" record
4. Replace `REPLACE_ME_WITH_REAL_DEEPGRAM_API_KEY` with your actual Deepgram API key
5. Save

#### Option B: Update the Metadata Files

**For Tavily:**
1. Edit `force-app/main/default/customMetadata/Tavily_API_Config__mdt.Default.md-meta.xml`
2. Replace `REPLACE_ME_WITH_REAL_TAVILY_API_KEY` with your actual API key
3. Redeploy the Custom Metadata record

**For Deepgram:**
1. Edit `force-app/main/default/customMetadata/Deepgram_API_Config__mdt.Default.md-meta.xml`
2. Replace `REPLACE_ME_WITH_REAL_DEEPGRAM_API_KEY` with your actual API key
3. Redeploy the Custom Metadata record

### Step 4: Deploy All Metadata

Deploy all API-related metadata:
```bash
sf project deploy start \
  --source-dir force-app/main/default/objects/Tavily_API_Config__mdt \
  --source-dir force-app/main/default/customMetadata/Tavily_API_Config__mdt \
  --source-dir force-app/main/default/remoteSiteSettings/Tavily_API \
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

After deployment, verify both configurations:

**Tavily API:**
1. **Check Custom Metadata**: Setup → Custom Metadata Types → Tavily API Config → Manage Records → Verify "Default" record has your API key
2. **Check Remote Site**: Setup → Remote Site Settings → Verify "Tavily_API" is active

**Deepgram API:**
1. **Check Custom Metadata**: Setup → Custom Metadata Types → Deepgram API Config → Manage Records → Verify "Default" record has your API key
2. **Check Remote Site**: Setup → Remote Site Settings → Verify "Deepgram_API" is active
3. **Check CSP Trusted Site**: Setup → CSP Trusted Sites → Verify "Deepgram_WebSocket" is active

## Testing

**Test Tavily API (Competitive Intelligence):**
1. Navigate to Meeting Command Center
2. Click "Prep for Meeting" on an upcoming event
3. Scroll to the "Competitive Intelligence" section
4. Verify that strategic analysis is generated (not showing "Error generating strategic analysis")

**Test Deepgram API (Voice Transcription):**
1. Navigate to Meeting Command Center
2. Click "Recap Meeting" on a past event
3. Click the microphone icon in the recap modal
4. Record audio and verify transcription appears

## Troubleshooting

### Tavily API Issues

**Error: "Tavily API key not configured"**
- Verify the Custom Metadata record exists with Developer Name "Default"
- Verify the API_Key__c field contains a valid API key (not the placeholder)

**Error: "Error generating strategic analysis"**
- Verify your Tavily API key is valid and active
- Check that Remote Site Setting "Tavily_API" is deployed and active
- Check browser console or debug logs for specific error messages

**Error: "Tavily API returned error: 401"**
- Your API key is invalid or expired
- Generate a new API key from Tavily dashboard

### Deepgram API Issues

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

- The placeholders `REPLACE_ME_WITH_REAL_TAVILY_API_KEY` and `REPLACE_ME_WITH_REAL_DEEPGRAM_API_KEY` are safe to commit
- Replace them with your real keys only in your deployment org
- Consider using Protected Custom Metadata for production orgs
- Use different API keys for different environments (dev, staging, production)

## Quick Start Summary

1. ✅ Sign up for free Tavily account → Get API key
2. ✅ Sign up for free Deepgram account → Get API key
3. ✅ Deploy metadata to Salesforce org
4. ✅ Update Custom Metadata records with your API keys
5. ✅ Test competitive intelligence and voice transcription features

Both services offer free tiers that are perfect for getting started!

