import { LightningElement, api, track } from "lwc";
import submitMeetingRecap from "@salesforce/apex/MeetingCommandCenterController.submitMeetingRecap";
import transcribeAudioChunk from "@salesforce/apex/MeetingCommandCenterController.transcribeAudioChunk";
import getAccountPrepInfo from "@salesforce/apex/MeetingCommandCenterController.getAccountPrepInfo";
import { NavigationMixin } from "lightning/navigation";
import AGENTFORCE_ICON from "@salesforce/resourceUrl/AgentforceRGBIcon";

export default class MeetingRecapModal extends NavigationMixin(
  LightningElement
) {
  @api eventId;
  @api eventSubject;
  @api accountName;
  @api accountId;
  @api contactName;
  @api contactId;

  @track recapText = "";
  @track isRecording = false;
  @track isProcessing = false;
  @track voiceError = null;
  @track processingMessage = "Analyzing your meeting notes...";
  @track accountInfo = null;
  @track isLoadingAccountInfo = false;
  @track isLoadingAccountSummary = false;

  agentforceIcon = AGENTFORCE_ICON;

  // Audio recording vars
  mediaRecorder = null;
  mediaStream = null;
  audioChunks = [];
  accumulatedTranscript = "";
  isConnecting = false;
  isTranscribing = false;

  processingMessages = [
    "Analyzing your meeting notes...",
    "Identifying key discussion points...",
    "Extracting action items...",
    "Generating AI summary...",
    "Updating event record..."
  ];
  processingMessageIndex = 0;
  processingInterval = null;

  connectedCallback() {
    // Initialize accountInfo with data passed from parent (available immediately)
    this.accountInfo = {
      accountId: this.accountId || null,
      accountName: this.accountName || null,
      contactId: this.contactId || null,
      contactName: this.contactName || null,
      accountSummary: null // Will be loaded via API call
    };
    this.isLoadingAccountSummary = true; // Show loading state for summary only
    this.loadAccountPrepInfo();
  }

  disconnectedCallback() {
    this.stopRecording();
    this.cleanup();
  }

  /**
   * Load account prep information (only the AI summary, account/contact already available)
   */
  async loadAccountPrepInfo() {
    if (!this.eventId) {
      return;
    }

    // Only load the AI summary - account/contact info is already available from props
    this.isLoadingAccountSummary = true;
    try {
      const result = await getAccountPrepInfo({ eventId: this.eventId });

      // Update account/contact IDs if they weren't passed as props (fallback)
      if (!this.accountInfo.accountId && result.accountId) {
        this.accountInfo.accountId = result.accountId;
      }
      if (!this.accountInfo.accountName && result.accountName) {
        this.accountInfo.accountName = result.accountName;
      }
      if (!this.accountInfo.contactId && result.contactId) {
        this.accountInfo.contactId = result.contactId;
      }
      if (!this.accountInfo.contactName && result.contactName) {
        this.accountInfo.contactName = result.contactName;
      }

      // Load the AI summary
      if (result.accountSummary) {
        this.accountInfo.accountSummary = result.accountSummary;
      }
      this.isLoadingAccountSummary = false;
    } catch (error) {
      console.error("Error loading account prep info:", error);
      // Don't show error to user, just log it
      this.isLoadingAccountSummary = false;
    }
  }

  /**
   * Navigate to account record
   */
  handleAccountClick() {
    if (this.accountInfo && this.accountInfo.accountId) {
      this[NavigationMixin.Navigate]({
        type: "standard__recordPage",
        attributes: {
          recordId: this.accountInfo.accountId,
          objectApiName: "Account",
          actionName: "view"
        }
      });
    }
  }

  /**
   * Navigate to contact record
   */
  handleContactClick() {
    if (this.accountInfo && this.accountInfo.contactId) {
      this[NavigationMixin.Navigate]({
        type: "standard__recordPage",
        attributes: {
          recordId: this.accountInfo.contactId,
          objectApiName: "Contact",
          actionName: "view"
        }
      });
    }
  }

  /**
   * Navigate to event record
   */
  handleEventClick() {
    if (this.eventId) {
      this[NavigationMixin.Navigate]({
        type: "standard__recordPage",
        attributes: {
          recordId: this.eventId,
          objectApiName: "Event",
          actionName: "view"
        }
      });
    }
  }

  /**
   * Start audio recording
   */
  async toggleVoiceRecording() {
    if (this.isRecording) {
      this.stopRecording();
      return;
    }

    try {
      // Request microphone access
      this.mediaStream = await navigator.mediaDevices.getUserMedia({
        audio: {
          channelCount: 1,
          sampleRate: 16000,
          echoCancellation: true,
          noiseSuppression: true,
          autoGainControl: true
        }
      });

      // Create MediaRecorder with WAV format
      const options = {
        mimeType: "audio/webm;codecs=opus",
        audioBitsPerSecond: 16000
      };

      // Fallback to default if webm not supported
      if (!MediaRecorder.isTypeSupported(options.mimeType)) {
        options.mimeType = "audio/webm";
      }

      this.mediaRecorder = new MediaRecorder(this.mediaStream, options);
      this.audioChunks = [];

      this.mediaRecorder.ondataavailable = (event) => {
        if (event.data && event.data.size > 0) {
          this.audioChunks.push(event.data);
        }
      };

      this.mediaRecorder.onstop = async () => {
        // Transcribe only when recording stops
        await this.transcribeRecording();
      };

      // Start recording - collect all data until stop
      this.mediaRecorder.start();

      this.isRecording = true;
      this.voiceError = null;
    } catch (error) {
      console.error("Error starting audio capture:", error);
      if (
        error.name === "NotAllowedError" ||
        error.name === "PermissionDeniedError"
      ) {
        this.voiceError =
          "Microphone access denied. Please enable microphone permissions.";
      } else if (error.name === "NotFoundError") {
        this.voiceError = "No microphone found. Please connect a microphone.";
      } else {
        this.voiceError = "Failed to access microphone: " + error.message;
      }
      this.isRecording = false;
    }
  }

  /**
   * Transcribe the complete recording after stop
   */
  async transcribeRecording() {
    if (this.audioChunks.length === 0) {
      return;
    }

    this.isTranscribing = true;
    this.voiceError = null;

    try {
      // Combine all audio chunks into a single blob
      const audioBlob = new Blob(this.audioChunks, { type: "audio/webm" });

      // Convert blob to base64
      const base64Audio = await this.blobToBase64(audioBlob);

      // Clear chunks after processing
      this.audioChunks = [];

      // Get existing text from textarea
      const existingText = this.recapText || "";

      // Send to Apex for transcription
      const transcript = await transcribeAudioChunk({
        audioBase64: base64Audio,
        existingText: existingText
      });

      if (transcript && transcript.trim().length > 0) {
        // Append transcription to existing text
        const newText = existingText
          ? existingText + " " + transcript.trim()
          : transcript.trim();

        this.recapText = newText;
        this.accumulatedTranscript = this.recapText;

        // Update textarea
        const textarea = this.template.querySelector("textarea");
        if (textarea) {
          textarea.value = this.recapText;
        }
      } else {
        this.voiceError = "No speech detected. Please try again.";
      }
    } catch (error) {
      console.error("Error transcribing recording:", error);
      if (error.body && error.body.message) {
        this.voiceError = "Transcription error: " + error.body.message;
      } else {
        this.voiceError = "Failed to transcribe recording. Please try again.";
      }
    } finally {
      this.isTranscribing = false;
    }
  }

  /**
   * Convert blob to base64 string
   */
  blobToBase64(blob) {
    return new Promise((resolve, reject) => {
      const reader = new FileReader();
      reader.onloadend = () => {
        // Remove data URL prefix (data:audio/webm;base64,)
        const base64 = reader.result.split(",")[1];
        resolve(base64);
      };
      reader.onerror = reject;
      reader.readAsDataURL(blob);
    });
  }

  /**
   * Stop recording
   */
  stopRecording() {
    if (this.mediaRecorder && this.mediaRecorder.state !== "inactive") {
      this.mediaRecorder.stop();
    }

    if (this.mediaStream) {
      this.mediaStream.getTracks().forEach((mediaTrack) => mediaTrack.stop());
      this.mediaStream = null;
    }

    this.isRecording = false;
  }

  /**
   * Cleanup resources
   */
  cleanup() {
    this.stopRecording();
    this.audioChunks = [];
  }

  handleTextChange(event) {
    const newValue = event.target.value || "";
    this.recapText = newValue;
    this.accumulatedTranscript = newValue;
  }

  renderedCallback() {
    // Ensure textarea value stays in sync
    const textarea = this.template.querySelector("textarea");
    if (textarea && textarea.value !== this.recapText) {
      textarea.value = this.recapText || "";
    }
  }

  handleClose() {
    this.cleanup();
    this.dispatchEvent(new CustomEvent("close"));
  }

  handleSave() {
    if (!this.recapText || this.recapText.trim().length === 0) {
      return;
    }

    if (this.isRecording) {
      this.stopRecording();
    }

    this.isProcessing = true;
    this.startProcessingMessages();

    submitMeetingRecap({
      eventId: this.eventId,
      recapText: this.recapText.trim()
    })
      .then((recapId) => {
        this.dispatchEvent(
          new CustomEvent("save", {
            detail: {
              eventId: this.eventId,
              recapId: recapId
            }
          })
        );
      })
      .catch((error) => {
        console.error("Error saving recap:", error);
        this.isProcessing = false;
        this.stopProcessingMessages();
        // Show the actual error message from the server
        const errorMessage =
          error.body?.message ||
          error.message ||
          "Failed to save recap. Please try again.";
        this.voiceError = errorMessage;
      });
  }

  startProcessingMessages() {
    this.processingMessageIndex = 0;
    this.processingMessage = this.processingMessages[0];

    // eslint-disable-next-line @lwc/lwc/no-async-operation
    this.processingInterval = setInterval(() => {
      this.processingMessageIndex =
        (this.processingMessageIndex + 1) % this.processingMessages.length;
      this.processingMessage =
        this.processingMessages[this.processingMessageIndex];
    }, 2000);
  }

  stopProcessingMessages() {
    if (this.processingInterval) {
      clearInterval(this.processingInterval);
      this.processingInterval = null;
    }
  }

  get charCount() {
    return this.recapText ? this.recapText.length : 0;
  }

  get isSaveDisabled() {
    return (
      this.isProcessing || !this.recapText || this.recapText.trim().length === 0
    );
  }

  get voiceButtonVariant() {
    if (this.isConnecting) {
      return "neutral";
    }
    return this.isRecording ? "destructive" : "brand";
  }

  get voiceButtonLabel() {
    if (this.isConnecting) {
      return "Connecting...";
    }
    return this.isRecording ? "Stop Speaking" : "Start Speaking";
  }

  get voiceButtonIcon() {
    if (this.isConnecting) {
      return "utility:spinner";
    }
    return this.isRecording ? "utility:stop" : "utility:record";
  }

  get isButtonDisabled() {
    return this.isConnecting || this.isTranscribing;
  }

  get summaryLabelText() {
    if (!this.accountInfo) {
      return "Agentforce Account Summary";
    }
    // If only contact exists (no account), show "Contact Summary"
    if (this.accountInfo.contactName && !this.accountInfo.accountName) {
      return "Agentforce Contact Summary";
    }
    // Default to Account Summary (even if accountName is null initially)
    return "Agentforce Account Summary";
  }

  get summaryLabelClass() {
    return this.isLoadingAccountSummary ? "summary-label-gradient" : "";
  }
}
