function asSamples(ms) {
  return Math.round(ms * sampleRate / 1000);
}

class MoshiProcessor extends AudioWorkletProcessor {
  constructor() {
    super();

    const frameSize = asSamples(80);
    this.initialBufferSamples = 1 * frameSize;
    this.partialBufferSamples = asSamples(10);
    this.maxBufferSamples = asSamples(10);
    this.partialBufferIncrement = asSamples(5);
    this.maxPartialWithIncrements = asSamples(80);
    this.maxBufferSamplesIncrement = asSamples(5);
    this.maxMaxBufferWithIncrements = asSamples(80);

    this.initState();

    this.port.onmessage = (event) => {
      if (event.data.type === 'reset') {
        this.initState();
        return;
      }

      const frame = event.data.frame;
      this.frames.push(frame);

      if (this.currentSamples() >= this.initialBufferSamples && !this.started) {
        this.start();
      }

      if (this.currentSamples() >= this.totalMaxBufferSamples()) {
        const target = this.initialBufferSamples + this.partialBufferSamples;
        while (this.currentSamples() > target) {
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
        this.maxBufferSamples = Math.min(
          this.maxBufferSamples + this.maxBufferSamplesIncrement,
          this.maxMaxBufferWithIncrements
        );
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
    this.remainingPartialBufferSamples = 0;
    this.timeInStream = 0;
    this.started = false;
    this.totalAudioPlayed = 0;
    this.actualAudioPlayed = 0;
    this.maxDelay = 0;
    this.minDelay = 2000;
    this.partialBufferSamples = asSamples(10);
    this.maxBufferSamples = asSamples(10);
  }

  totalMaxBufferSamples() {
    return this.maxBufferSamples + this.partialBufferSamples + this.initialBufferSamples;
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
    this.remainingPartialBufferSamples = this.partialBufferSamples;
    this.firstOut = true;
  }

  canPlay() {
    return this.started && this.frames.length > 0 && this.remainingPartialBufferSamples <= 0;
  }

  process(inputs, outputs) {
    const output = outputs[0][0];
    if (!output) return true;

    if (!this.canPlay()) {
      if (this.actualAudioPlayed > 0) {
        this.totalAudioPlayed += output.length / sampleRate;
      }
      this.remainingPartialBufferSamples -= output.length;
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
      this.partialBufferSamples = Math.min(
        this.partialBufferSamples + this.partialBufferIncrement,
        this.maxPartialWithIncrements
      );
      this.started = false;
      this.remainingPartialBufferSamples = 0;
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
