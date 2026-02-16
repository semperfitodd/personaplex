const MSG = {
  HANDSHAKE: 0x00,
  AUDIO: 0x01,
  TEXT: 0x02,
  CONTROL: 0x03,
  METADATA: 0x04,
  ERROR: 0x05,
  PING: 0x06,
};

const CONTROL_ACTION_REV = {
  0x00: 'start',
  0x01: 'endTurn',
  0x02: 'pause',
  0x03: 'restart',
};

export function encodeAudio(data) {
  const msg = new Uint8Array(1 + data.length);
  msg[0] = MSG.AUDIO;
  msg.set(data, 1);
  return msg;
}

export function decodeMessage(data) {
  const type = data[0];
  const payload = data.slice(1);

  switch (type) {
    case MSG.HANDSHAKE:
      return { type: 'handshake' };
    case MSG.AUDIO:
      return { type: 'audio', data: payload };
    case MSG.TEXT:
      return { type: 'text', data: new TextDecoder().decode(payload) };
    case MSG.CONTROL:
      return { type: 'control', action: CONTROL_ACTION_REV[payload[0]] || 'unknown' };
    case MSG.METADATA:
      return { type: 'metadata', data: JSON.parse(new TextDecoder().decode(payload)) };
    case MSG.ERROR:
      return { type: 'error', data: new TextDecoder().decode(payload) };
    case MSG.PING:
      return { type: 'ping' };
    default:
      return { type: 'unknown', rawType: type };
  }
}
