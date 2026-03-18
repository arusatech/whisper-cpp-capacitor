const mockPlugin = {
  initContext: jest.fn(),
  releaseContext: jest.fn(),
  releaseAllContexts: jest.fn(),
  transcribe: jest.fn(),
  transcribeRealtime: jest.fn(),
  stopTranscription: jest.fn(),
  loadModel: jest.fn(),
  unloadModel: jest.fn(),
  getModelInfo: jest.fn(),
  getAudioFormat: jest.fn(),
  convertAudio: jest.fn(),
  getSystemInfo: jest.fn(),
  addListener: jest.fn(),
  removeAllListeners: jest.fn(),
};

export const registerPlugin = jest.fn(() => mockPlugin);

export default { registerPlugin };
