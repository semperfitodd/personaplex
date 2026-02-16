/**
 * Moshi/PersonaPlex WebSocket binary protocol encoder/decoder.
 *
 * Wire format: first byte = message type, rest = payload.
 *   0x00 handshake  [version, model]
 *   0x01 audio      [opus/ogg bytes]
 *   0x02 text       [utf-8 string]
 *   0x03 control    [action byte]
 *   0x04 metadata   [json utf-8]
 *   0x05 error      [utf-8 string]
 *   0x06 ping       (no payload)
 */

const MSG = {
  HANDSHAKE: 0x00,
  AUDIO: 0x01,
  TEXT: 0x02,
  CONTROL: 0x03,
  METADATA: 0x04,
  ERROR: 0x05,
  PING: 0x06,
};

const CONTROL_ACTION = {
  start: 0x00,
  endTurn: 0x01,
  pause: 0x02,
  restart: 0x03,
};

const CONTROL_ACTION_REV = Object.fromEntries(
  Object.entries(CONTROL_ACTION).map(([k, v]) => [v, k])
);

export function encodeHandshake() {
  return new Uint8Array([MSG.HANDSHAKE, 0x00, 0x00]);
}

export function encodeAudio(data) {
  const msg = new Uint8Array(1 + data.length);
  msg[0] = MSG.AUDIO;
  msg.set(data, 1);
  return msg;
}

export function encodeControl(action) {
  return new Uint8Array([MSG.CONTROL, CONTROL_ACTION[action]]);
}

export function encodeMetadata(data) {
  const json = new TextEncoder().encode(JSON.stringify(data));
  const msg = new Uint8Array(1 + json.length);
  msg[0] = MSG.METADATA;
  msg.set(json, 1);
  return msg;
}

export function encodePing() {
  return new Uint8Array([MSG.PING]);
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
      console.warn('Unknown message type:', type);
      return { type: 'unknown', rawType: type };
  }
}
