function asSamples(ms) {
  return Math.round(ms * sampleRate / 1000);
}

class MoshiProcessor extends AudioWorkletProcessor {
  constructor() {
    super();

    const frameSize = asSamples(80);

    // First connection: wait for a full 4-frame prebuffer (320ms) so the model
    // has time to warm up and fill the pipeline before playback starts.
    this.initialBufferSamples = 4 * frameSize;

    // After any underrun: resume as soon as a single frame (80ms) arrives.
    // This keeps silence gaps to ~80-100ms instead of the full re-buffer cost.
    this.resumeBufferSamples = 1 * frameSize;

    // Jitter pad added after the initial start only (absorbs early variance).
    // No pad on resume — we want to restart immediately.
    this.initialPartialSamples = asSamples(40);

    // Overflow protection: drop oldest frames when buffer grows too large.
    this.maxBufferSamples = asSamples(600);

    this.initState();

    this.port.onmessage = (event) => {
      if (event.data.type === 'reset') {
        this.initState();
        return;
      }

      const frame = event.data.frame;
      this.frames.push(frame);

      if (!this.started) {
        const threshold = this.hasStarted
          ? this.resumeBufferSamples
          : this.initialBufferSamples;
        if (this.currentSamples() >= threshold) {
          this.start();
        }
      }

      // Drop oldest frames if buffer grows too large (model running fast or
      // connection resumed after a long pause).
      if (this.currentSamples() > this.maxBufferSamples) {
        const target = Math.round(this.maxBufferSamples * 0.75);
        while (this.currentSamples() > target && this.frames.length) {
          const first = this.frames[0];
          const toRemove = Math.min(
            first.length - this.offsetInFirstBuffer,
            this.currentSamples() - target
          );
          this.offsetInFirstBuffer += toRemove;
          this.timeInStream += toRemove / sampleRate;
          if (this.offsetInFirstBuffer === first.length) {
            this.frames.shift();
            this.offsetInFirstBuffer = 0;
          }
        }
      }

      this.port.postMessage({
        totalAudioPlayed: this.totalAudioPlayed,
        actualAudioPlayed: this.actualAudioPlayed,
        delay: event.data.micDuration - this.timeInStream,
        minDelay: this.minDelay,
        maxDelay: this.maxDelay,
      });
    };
  }

  initState() {
    this.frames = [];
    this.offsetInFirstBuffer = 0;
    this.firstOut = false;
    this.remainingPartialSamples = 0;
    this.timeInStream = 0;
    this.started = false;
    this.hasStarted = false;
    this.totalAudioPlayed = 0;
    this.actualAudioPlayed = 0;
    this.maxDelay = 0;
    this.minDelay = 2000;
  }

  currentSamples() {
    let samples = 0;
    for (let k = 0; k < this.frames.length; k++) {
      samples += this.frames[k].length;
    }
    return samples - this.offsetInFirstBuffer;
  }

  start() {
    this.started = true;
    // Only apply the jitter pad on the very first start.
    this.remainingPartialSamples = this.hasStarted ? 0 : this.initialPartialSamples;
    this.firstOut = true;
    this.hasStarted = true;
  }

  canPlay() {
    return this.started && this.frames.length > 0 && this.remainingPartialSamples <= 0;
  }

  process(inputs, outputs) {
    const output = outputs[0][0];
    if (!output) return true;

    if (!this.canPlay()) {
      if (this.actualAudioPlayed > 0) {
        this.totalAudioPlayed += output.length / sampleRate;
      }
      this.remainingPartialSamples -= output.length;
      return true;
    }

    const delay = this.currentSamples() / sampleRate;
    this.maxDelay = Math.max(this.maxDelay, delay);
    this.minDelay = Math.min(this.minDelay, delay);

    let outIdx = 0;
    while (outIdx < output.length && this.frames.length) {
      const first = this.frames[0];
      const toCopy = Math.min(
        first.length - this.offsetInFirstBuffer,
        output.length - outIdx
      );
      output.set(
        first.subarray(this.offsetInFirstBuffer, this.offsetInFirstBuffer + toCopy),
        outIdx
      );
      this.offsetInFirstBuffer += toCopy;
      outIdx += toCopy;
      if (this.offsetInFirstBuffer === first.length) {
        this.offsetInFirstBuffer = 0;
        this.frames.shift();
      }
    }

    if (this.firstOut) {
      this.firstOut = false;
      for (let i = 0; i < outIdx; i++) {
        output[i] *= i / outIdx;
      }
    }

    if (outIdx < output.length) {
      // Underrun: fade out what we have and reset to resume mode.
      // Do NOT grow any buffer thresholds — that makes each pause longer.
      this.started = false;
      this.remainingPartialSamples = 0;
      for (let i = 0; i < outIdx; i++) {
        output[i] *= (outIdx - i) / outIdx;
      }
    }

    this.totalAudioPlayed += output.length / sampleRate;
    this.actualAudioPlayed += outIdx / sampleRate;
    this.timeInStream += outIdx / sampleRate;
    return true;
  }
}

registerProcessor('moshi-processor', MoshiProcessor);
