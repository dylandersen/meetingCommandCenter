import { LightningElement, api, track } from "lwc";
import generateRecapInsights from "@salesforce/apex/MeetingCommandCenterController.generateRecapInsights";
import getOpportunitySnapshot from "@salesforce/apex/MeetingCommandCenterController.getOpportunitySnapshot";
import commitRecap from "@salesforce/apex/MeetingCommandCenterController.commitRecap";
import transcribeAudioChunk from "@salesforce/apex/MeetingCommandCenterController.transcribeAudioChunk";
import getAccountPrepInfo from "@salesforce/apex/MeetingCommandCenterController.getAccountPrepInfo";
import { NavigationMixin } from "lightning/navigation";
import AGENTFORCE_ICON from "@salesforce/resourceUrl/AgentforceRGBIcon";

// Opportunity fields the rep most often updates from a meeting recap.
const OPP_FIELD_DEFS = [
  { key: "amount", label: "Amount", type: "currency", api: "Amount" },
  { key: "closeDate", label: "Close Date", type: "date", api: "CloseDate" },
  { key: "stageName", label: "Stage", type: "combobox", api: "StageName" },
  { key: "nextStep", label: "Next Step", type: "text", api: "NextStep" }
];

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

  // Review step (post-analysis, pre-save)
  @track reviewMode = false;
  @track oppFieldRows = [];
  @track taskRows = [];
  @track summaryPreview = null;
  @track keyOutcomesPreview = null;
  @track nextStepsPreview = null;
  @track hasOpportunity = false;
  @track editingSummary = false;
  @track editingOutcomes = false;
  @track editingNextSteps = false;
  @track opportunityIdForCommit = null;
  @track opportunityNameForCommit = null;
  @track changingOpportunity = false;
  // Raw AI-suggested opportunity values (transcript-derived, opp-agnostic) kept
  // so we can re-diff against a different opportunity if the rep changes it.
  oppSuggested = {};
  oppCurrent = {};
  oppStageOptions = [];
  relatedToLabel = "";
  relatedToObjectApiName = null;
  assignedToLabel = "";
  commitContext = { accountId: null, contactId: null };
  taskKeySeq = 0;

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

  @track isAccountLoading = false;

  connectedCallback() {
    // Contact info is reliable from the parent and can be shown immediately.
    // The parent passes the Event's polymorphic What (id + name). We use the
    // record ID key prefix to label it correctly up front so all fields render
    // immediately and don't shift around once the Apex call returns:
    //   001 => Account, 006 => Opportunity
    const whatId = this.accountId || null;
    const whatName = this.accountName || null;
    const prefix = whatId ? whatId.substring(0, 3) : null;

    let accountId = null;
    let accountName = null;
    let opportunityId = null;
    let opportunityName = null;
    let accountLoading = false;

    if (prefix === "006") {
      // What is an Opportunity. Show it now; its Account is resolved via Apex,
      // so reserve the Account row with a loading placeholder.
      opportunityId = whatId;
      opportunityName = whatName;
      accountLoading = true;
    } else if (prefix === "001") {
      // What is an Account.
      accountId = whatId;
      accountName = whatName;
    }

    this.accountInfo = {
      accountId,
      accountName,
      opportunityId,
      opportunityName,
      contactId: this.contactId || null,
      contactName: this.contactName || null,
      accountSummary: null // Will be loaded via API call
    };
    this.isAccountLoading = accountLoading;
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

    this.isLoadingAccountSummary = true;
    try {
      const result = await getAccountPrepInfo({ eventId: this.eventId });

      // The Apex call is authoritative and fills in any fields that weren't
      // resolvable up front (e.g. the Account behind an Opportunity) plus the
      // AI summary. Prefer existing values to avoid flicker.
      this.accountInfo = {
        ...this.accountInfo,
        accountId: result.accountId || this.accountInfo.accountId || null,
        accountName: result.accountName || this.accountInfo.accountName || null,
        opportunityId:
          result.opportunityId || this.accountInfo.opportunityId || null,
        opportunityName:
          result.opportunityName || this.accountInfo.opportunityName || null,
        contactId: result.contactId || this.accountInfo.contactId || null,
        contactName: result.contactName || this.accountInfo.contactName || null,
        accountSummary: result.accountSummary || null
      };

      this.isAccountLoading = false;
      this.isLoadingAccountSummary = false;
    } catch (error) {
      console.error("Error loading account prep info:", error);
      // Don't show error to user, just log it
      this.isAccountLoading = false;
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
   * Navigate to opportunity record
   */
  handleOpportunityClick() {
    if (this.accountInfo && this.accountInfo.opportunityId) {
      this[NavigationMixin.Navigate]({
        type: "standard__recordPage",
        attributes: {
          recordId: this.accountInfo.opportunityId,
          objectApiName: "Opportunity",
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
      
      if (!audioBlob || audioBlob.size === 0) {
        throw new Error("No audio data recorded. Please try recording again.");
      }

      // Convert blob to base64
      let base64Audio;
      try {
        base64Audio = await this.blobToBase64(audioBlob);
        if (!base64Audio || base64Audio.trim().length === 0) {
          throw new Error("Failed to encode audio data.");
        }
      } catch (encodeError) {
        console.error("Error encoding audio:", encodeError);
        throw new Error("Failed to process audio recording. Please try again.");
      }

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
      let errorMessage = "Failed to transcribe recording. Please try again.";
      
      if (error.body) {
        if (error.body.message) {
          // Use the error message from Apex (it already includes "Transcription error:" prefix if needed)
          errorMessage = error.body.message;
        } else if (error.body.pageErrors && error.body.pageErrors.length > 0) {
          errorMessage = error.body.pageErrors[0].message;
        } else if (error.body.fieldErrors) {
          // Handle field errors if any
          const fieldErrors = Object.values(error.body.fieldErrors);
          if (fieldErrors.length > 0 && fieldErrors[0].length > 0) {
            errorMessage = fieldErrors[0][0].message;
          }
        }
      } else if (error.message) {
        errorMessage = error.message;
      }
      
      this.voiceError = errorMessage;
    } finally {
      this.isTranscribing = false;
    }
  }

  /**
   * Convert blob to base64 string
   */
  blobToBase64(blob) {
    return new Promise((resolve, reject) => {
      if (!blob) {
        reject(new Error("Invalid blob data"));
        return;
      }
      
      const reader = new FileReader();
      reader.onloadend = () => {
        try {
          if (!reader.result) {
            reject(new Error("Failed to read blob data"));
            return;
          }
          // Remove data URL prefix (data:audio/webm;base64,)
          const parts = reader.result.split(",");
          if (parts.length < 2) {
            reject(new Error("Invalid data URL format"));
            return;
          }
          const base64 = parts[1];
          if (!base64 || base64.trim().length === 0) {
            reject(new Error("Empty base64 data"));
            return;
          }
          resolve(base64);
        } catch (error) {
          reject(new Error("Error processing blob: " + error.message));
        }
      };
      reader.onerror = (error) => {
        reject(new Error("FileReader error: " + (error.message || "Unknown error")));
      };
      try {
        reader.readAsDataURL(blob);
      } catch (error) {
        reject(new Error("Error reading blob: " + error.message));
      }
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

  /**
   * Step 1: analyze the notes. Generates the AI summary plus suggested
   * Opportunity updates and follow-up tasks, then shows the review step.
   * Nothing is committed to the database yet.
   */
  handleAnalyze() {
    if (!this.recapText || this.recapText.trim().length === 0) {
      return;
    }

    if (this.isRecording) {
      this.stopRecording();
    }

    this.voiceError = null;
    this.isProcessing = true;
    this.startProcessingMessages();

    generateRecapInsights({
      eventId: this.eventId,
      recapText: this.recapText.trim()
    })
      .then((insights) => {
        this.buildReview(insights);
        this.isProcessing = false;
        this.stopProcessingMessages();
        this.reviewMode = true;
      })
      .catch((error) => {
        console.error("Error analyzing recap:", error);
        this.isProcessing = false;
        this.stopProcessingMessages();
        this.voiceError =
          error.body?.message ||
          error.message ||
          "Failed to analyze recap. Please try again.";
      });
  }

  /**
   * Transforms the Apex insights payload into editable view-model rows.
   */
  buildReview(insights) {
    this.summaryPreview = insights.summary || null;
    this.keyOutcomesPreview = insights.keyOutcomes || null;
    this.nextStepsPreview = insights.nextSteps || null;

    this.commitContext = {
      accountId: insights.accountId || null,
      contactId: insights.contactId || null
    };
    this.assignedToLabel = insights.currentUserName || "Me";

    const opp = insights.opportunity || {};
    this.hasOpportunity = opp.hasOpportunity === true;
    this.opportunityIdForCommit = insights.opportunityId || opp.id || null;
    this.opportunityNameForCommit =
      insights.opportunityName || opp.name || null;
    this.relatedToLabel =
      this.opportunityNameForCommit || insights.accountName || "—";

    // Default "Related To" target for follow-up tasks: the Opportunity if we
    // have one, otherwise the Account.
    const defaultRelatedId =
      this.opportunityIdForCommit || insights.accountId || null;
    this.relatedToObjectApiName = this.opportunityIdForCommit
      ? "Opportunity"
      : insights.accountId
        ? "Account"
        : null;

    // Keep the AI's transcript-derived suggestions (and the current opp values)
    // so the rows can be recomputed if the rep changes the target opportunity.
    this.oppSuggested = opp.suggested || {};
    this.oppCurrent = opp.current || {};
    this.oppStageOptions = opp.stageOptions || [];
    this.oppFieldRows = this.computeOppRows();

    // Build editable task rows.
    const tasks = Array.isArray(insights.tasks) ? insights.tasks : [];
    this.taskRows = tasks
      .filter((t) => t && (t.subject || "").trim().length > 0)
      .map((t) => ({
        id: `task-${this.taskKeySeq++}`,
        subject: t.subject || "",
        description: t.description || "",
        dueDate: t.dueDate || "",
        relatedToId: defaultRelatedId,
        include: true
      }));

    // Reset inline-edit toggles each time we (re)enter review.
    this.editingSummary = false;
    this.editingOutcomes = false;
    this.editingNextSteps = false;
  }

  // Builds the current -> suggested rows for whichever opportunity is currently
  // targeted, comparing the AI's transcript-derived suggestions against that
  // opportunity's current field values.
  computeOppRows() {
    const rows = [];
    const current = this.oppCurrent || {};
    const suggested = this.oppSuggested || {};
    const stageOptions = this.oppStageOptions || [];
    OPP_FIELD_DEFS.forEach((def) => {
      const suggestedVal = suggested[def.key];
      if (suggestedVal === null || suggestedVal === undefined) {
        return;
      }
      const currentVal = current[def.key];
      if (this.valuesEqual(def, currentVal, suggestedVal)) {
        return;
      }
      rows.push({
        key: def.key,
        label: def.label,
        apply: true,
        value: String(suggestedVal),
        aiSuggested: String(suggestedVal),
        currentDisplay: this.formatCurrent(def, currentVal),
        options: def.type === "combobox" ? stageOptions : null,
        isCurrency: def.type === "currency",
        isDate: def.type === "date",
        isCombobox: def.type === "combobox",
        isText: def.type === "text"
      });
    });
    return rows;
  }

  // Rep changed the target Opportunity via the record picker: pull that
  // opportunity's current values and re-diff the AI suggestions against it.
  handleOpportunityChange(event) {
    const recordId = event.detail.recordId;
    if (!recordId || recordId === this.opportunityIdForCommit) {
      return;
    }
    this.changingOpportunity = true;
    getOpportunitySnapshot({ opportunityId: recordId })
      .then((snap) => {
        this.opportunityIdForCommit = snap.id;
        this.opportunityNameForCommit = snap.name;
        this.relatedToLabel = snap.name;
        this.hasOpportunity = true;
        this.oppCurrent = snap.current || {};
        this.oppStageOptions = snap.stageOptions || [];
        this.oppFieldRows = this.computeOppRows();
        this.changingOpportunity = false;
      })
      .catch((error) => {
        console.error("Error loading opportunity snapshot:", error);
        this.changingOpportunity = false;
        this.voiceError =
          error.body?.message ||
          error.message ||
          "Could not load that opportunity. Please try another.";
      });
  }

  valuesEqual(def, currentVal, suggestedVal) {
    if (currentVal === null || currentVal === undefined) {
      return false;
    }
    if (def.type === "currency") {
      return Number(currentVal) === Number(suggestedVal);
    }
    return (
      String(currentVal).trim() === String(suggestedVal).trim()
    );
  }

  formatCurrent(def, currentVal) {
    if (currentVal === null || currentVal === undefined || currentVal === "") {
      return "—";
    }
    if (def.type === "currency") {
      const num = Number(currentVal);
      return Number.isNaN(num)
        ? String(currentVal)
        : num.toLocaleString(undefined, {
            style: "currency",
            currency: "USD",
            maximumFractionDigits: 0
          });
    }
    if (def.type === "date") {
      const d = new Date(`${currentVal}T00:00:00`);
      return Number.isNaN(d.getTime())
        ? String(currentVal)
        : d.toLocaleDateString(undefined, {
            month: "short",
            day: "numeric",
            year: "numeric"
          });
    }
    return String(currentVal);
  }

  handleOppValueChange(event) {
    const key = event.target.dataset.key;
    const value = event.target.value;
    this.oppFieldRows = this.oppFieldRows.map((row) =>
      row.key === key ? { ...row, value } : row
    );
  }

  handleOppApplyToggle(event) {
    const key = event.target.dataset.key;
    const checked = event.target.checked;
    this.oppFieldRows = this.oppFieldRows.map((row) =>
      row.key === key ? { ...row, apply: checked } : row
    );
  }

  handleTaskFieldChange(event) {
    const id = event.target.dataset.id;
    const field = event.target.dataset.field;
    const value = event.target.value;
    this.taskRows = this.taskRows.map((row) =>
      row.id === id ? { ...row, [field]: value } : row
    );
  }

  handleTaskIncludeToggle(event) {
    const id = event.target.dataset.id;
    const checked = event.target.checked;
    this.taskRows = this.taskRows.map((row) =>
      row.id === id ? { ...row, include: checked } : row
    );
  }

  handleRemoveTask(event) {
    const id = event.currentTarget.dataset.id;
    this.taskRows = this.taskRows.filter((row) => row.id !== id);
  }

  handleAddTask() {
    this.taskRows = [
      ...this.taskRows,
      {
        id: `task-${this.taskKeySeq++}`,
        subject: "",
        description: "",
        dueDate: "",
        relatedToId: this.opportunityIdForCommit || this.commitContext.accountId,
        include: true
      }
    ];
  }

  handleTaskRelatedChange(event) {
    const id = event.target.dataset.id;
    const recordId = event.detail ? event.detail.recordId : null;
    this.taskRows = this.taskRows.map((row) =>
      row.id === id ? { ...row, relatedToId: recordId } : row
    );
  }

  toggleEditSummary() {
    this.editingSummary = !this.editingSummary;
  }

  toggleEditOutcomes() {
    this.editingOutcomes = !this.editingOutcomes;
  }

  toggleEditNextSteps() {
    this.editingNextSteps = !this.editingNextSteps;
  }

  handleSummaryChange(event) {
    this.summaryPreview = event.target.value;
  }

  handleOutcomesChange(event) {
    this.keyOutcomesPreview = event.target.value;
  }

  handleNextStepsChange(event) {
    this.nextStepsPreview = event.target.value;
  }

  handleBackToEdit() {
    this.reviewMode = false;
    this.voiceError = null;
  }

  /**
   * Step 2: commit the reviewed (and possibly edited) recap, Opportunity
   * updates, and follow-up tasks.
   */
  handleConfirmSave() {
    const opportunityUpdates = {};
    const changes = [];
    this.oppFieldRows.forEach((row) => {
      if (!row.apply) {
        return;
      }
      if (row.key === "amount") {
        const num = parseFloat(row.value);
        if (!Number.isNaN(num)) {
          opportunityUpdates.amount = num;
        }
      } else if (row.value !== null && row.value !== undefined) {
        opportunityUpdates[row.key] = row.value;
      }

      // Capture an audit row of what changed for the recap display.
      const def = OPP_FIELD_DEFS.find((d) => d.key === row.key);
      const aiRaw = row.aiSuggested === undefined ? "" : row.aiSuggested;
      const newRaw = row.value === undefined ? "" : row.value;
      const overridden = String(aiRaw).trim() !== String(newRaw).trim();
      changes.push({
        fieldLabel: row.label,
        fieldApiName: def ? def.api : row.key,
        objectName: "Opportunity",
        targetRecordId: this.opportunityIdForCommit,
        previousValue: row.currentDisplay,
        newValue: this.formatCurrent(def, row.value),
        aiSuggestedValue: this.formatCurrent(def, row.aiSuggested),
        overridden
      });
    });

    const tasks = this.taskRows
      .filter((row) => row.include && (row.subject || "").trim().length > 0)
      .map((row) => ({
        subject: row.subject.trim(),
        description: row.description || "",
        dueDate: row.dueDate || null,
        whatId: row.relatedToId || null
      }));

    const payload = {
      eventId: this.eventId,
      recapText: this.recapText.trim(),
      summary: this.summaryPreview,
      keyOutcomes: this.keyOutcomesPreview,
      nextSteps: this.nextStepsPreview,
      opportunityId: this.opportunityIdForCommit,
      opportunityUpdates,
      changes,
      tasks,
      accountId: this.commitContext.accountId,
      contactId: this.commitContext.contactId
    };

    this.isProcessing = true;
    this.startProcessingMessages();

    commitRecap({ payloadJson: JSON.stringify(payload) })
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
        this.voiceError =
          error.body?.message ||
          error.message ||
          "Failed to save recap. Please try again.";
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

  get showAccountRow() {
    return Boolean(
      this.isAccountLoading || (this.accountInfo && this.accountInfo.accountName)
    );
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

  get hasOppSuggestions() {
    return this.hasOpportunity && this.oppFieldRows.length > 0;
  }

  get hasOppRows() {
    return this.oppFieldRows.length > 0;
  }

  get hasNoOppRows() {
    return this.oppFieldRows.length === 0;
  }

  get hasTasks() {
    return this.taskRows.length > 0;
  }

  get hasNoSuggestions() {
    return !this.hasOpportunity && !this.hasTasks;
  }

  get analyzeButtonDisabled() {
    return (
      this.isProcessing || !this.recapText || this.recapText.trim().length === 0
    );
  }

  get summaryEditIcon() {
    return this.editingSummary ? "utility:check" : "utility:edit";
  }

  get outcomesEditIcon() {
    return this.editingOutcomes ? "utility:check" : "utility:edit";
  }

  get nextStepsEditIcon() {
    return this.editingNextSteps ? "utility:check" : "utility:edit";
  }
}
