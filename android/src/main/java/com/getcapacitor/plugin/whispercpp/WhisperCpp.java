package com.getcapacitor.plugin.whispercpp;

import android.Manifest;
import android.content.Context;
import android.content.pm.PackageManager;
import android.media.AudioFormat;
import android.media.AudioRecord;
import android.media.MediaCodec;
import android.media.MediaExtractor;
import android.media.MediaFormat;
import android.media.MediaRecorder;
import android.os.Handler;
import android.os.Looper;
import android.util.Base64;
import android.util.Log;
import com.getcapacitor.JSObject;
import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

public class WhisperCpp {
    private static final String TAG = "WhisperCpp";
    private static final int SAMPLE_RATE = 16000;

    private final Context context;
    private final ExecutorService executor = Executors.newSingleThreadExecutor();
    private final Handler mainHandler = new Handler(Looper.getMainLooper());

    private StreamingSession activeSession;
    private final Object sessionLock = new Object();

    public WhisperCpp(Context context) {
        this.context = context.getApplicationContext();
    }

    // ---- Callback interfaces ----

    public interface ResultCallback<T> {
        void onResult(Result<T> result);
    }

    public interface SegmentCallback {
        void onSegment(JSObject segment);
    }

    public interface ErrorCallback {
        void onError(String message);
    }

    public interface ProgressCallback {
        void onProgress(int progress);
    }

    // ---- Result wrapper ----

    public static class Result<T> {
        final T data;
        final Throwable error;
        private Result(T data, Throwable error) {
            this.data = data;
            this.error = error;
        }
        public static <T> Result<T> success(T data) { return new Result<>(data, null); }
        public static <T> Result<T> error(Throwable e) { return new Result<>(null, e); }
        public boolean isSuccess() { return error == null; }
        public T getData() { return data; }
        public Throwable getError() { return error; }
    }

    // ---- Helpers ----

    private void runOnMain(Runnable r) {
        mainHandler.post(r);
    }

    private JSObject jsonToJSObject(String json) {
        if (json == null || json.isEmpty()) return new JSObject();
        try {
            return new JSObject(json);
        } catch (JSONException e) {
            return new JSObject();
        }
    }

    // ---- Existing methods ----

    public void initContext(String modelPath, JSObject params, ResultCallback<JSObject> callback) {
        executor.execute(() -> {
            try {
                String json = NativeBridge.initContext(modelPath, params != null ? params.toString() : "{}");
                JSObject result = jsonToJSObject(json);
                runOnMain(() -> callback.onResult(json != null && !json.isEmpty() ? Result.success(result) : Result.error(new Error("Init failed"))));
            } catch (Exception e) {
                Log.e(TAG, "initContext", e);
                runOnMain(() -> callback.onResult(Result.error(e)));
            }
        });
    }

    public void releaseContext(int contextId, ResultCallback<Void> callback) {
        executor.execute(() -> {
            try {
                boolean ok = NativeBridge.releaseContext(contextId);
                runOnMain(() -> callback.onResult(ok ? Result.success(null) : Result.error(new Error("Context not found"))));
            } catch (Exception e) {
                Log.e(TAG, "releaseContext", e);
                runOnMain(() -> callback.onResult(Result.error(e)));
            }
        });
    }

    public void releaseAllContexts(ResultCallback<Void> callback) {
        executor.execute(() -> {
            try {
                NativeBridge.releaseAllContexts();
                runOnMain(() -> callback.onResult(Result.success(null)));
            } catch (Exception e) {
                Log.e(TAG, "releaseAllContexts", e);
                runOnMain(() -> callback.onResult(Result.error(e)));
            }
        });
    }

    public void transcribe(String audioData, boolean isAudioFile, JSObject params, ResultCallback<JSObject> callback) {
        transcribe(audioData, isAudioFile, params, null, callback);
    }

    public void transcribe(String audioData, boolean isAudioFile, JSObject params, ProgressCallback progressCallback, ResultCallback<JSObject> callback) {
        int contextId = (params != null && params.has("contextId")) ? params.optInt("contextId", 0) : 0;
        executor.execute(() -> {
            try {
                String actualAudioData = audioData;
                boolean actualIsAudioFile = isAudioFile;

                // For non-WAV audio files, decode in Java using MediaCodec
                if (isAudioFile) {
                    String ext = extensionFromPath(audioData);
                    if (ext != null && !ext.equals("wav")) {
                        float[] samples = decodeAudioFile(audioData);
                        actualAudioData = floatArrayToBase64(samples);
                        actualIsAudioFile = false;
                        Log.i(TAG, "Decoded " + ext + " file to " + samples.length + " PCM samples");
                    }
                }

                String json;
                if (progressCallback != null) {
                    json = NativeBridge.transcribeWithProgress(contextId, actualAudioData, actualIsAudioFile,
                            params != null ? params.toString() : "{}", progressCallback);
                } else {
                    json = NativeBridge.transcribe(contextId, actualAudioData, actualIsAudioFile,
                            params != null ? params.toString() : "{}");
                }
                JSObject result = jsonToJSObject(json);
                runOnMain(() -> callback.onResult(json != null && !json.isEmpty() ? Result.success(result) : Result.error(new Error("Transcribe failed"))));
            } catch (Exception e) {
                Log.e(TAG, "transcribe", e);
                runOnMain(() -> callback.onResult(Result.error(e)));
            }
        });
    }

    public void getSystemInfo(ResultCallback<JSObject> callback) {
        executor.execute(() -> {
            try {
                JSObject info = new JSObject();
                info.put("platform", "android");
                info.put("gpu_available", false);
                info.put("max_threads", Runtime.getRuntime().availableProcessors());
                info.put("memory_available_mb", Runtime.getRuntime().maxMemory() / (1024 * 1024));
                runOnMain(() -> callback.onResult(Result.success(info)));
            } catch (Exception e) {
                Log.e(TAG, "getSystemInfo", e);
                runOnMain(() -> callback.onResult(Result.error(e)));
            }
        });
    }

    // ---- Audio format inspection ----

    public void getAudioFormat(String path, ResultCallback<JSObject> callback) {
        executor.execute(() -> {
            MediaExtractor extractor = new MediaExtractor();
            try {
                extractor.setDataSource(path);

                // Find the first audio track
                MediaFormat format = null;
                for (int i = 0; i < extractor.getTrackCount(); i++) {
                    MediaFormat trackFormat = extractor.getTrackFormat(i);
                    String mime = trackFormat.getString(MediaFormat.KEY_MIME);
                    if (mime != null && mime.startsWith("audio/")) {
                        format = trackFormat;
                        break;
                    }
                }

                if (format == null) {
                    runOnMain(() -> callback.onResult(Result.error(new Error("No audio track found"))));
                    return;
                }

                int sampleRate = format.getInteger(MediaFormat.KEY_SAMPLE_RATE);
                int channels = format.getInteger(MediaFormat.KEY_CHANNEL_COUNT);

                // Determine bits per sample from PCM encoding if available
                int bitsPerSample = 16; // default
                if (format.containsKey(MediaFormat.KEY_PCM_ENCODING)) {
                    int encoding = format.getInteger(MediaFormat.KEY_PCM_ENCODING);
                    if (encoding == AudioFormat.ENCODING_PCM_FLOAT) {
                        bitsPerSample = 32;
                    } else if (encoding == AudioFormat.ENCODING_PCM_16BIT) {
                        bitsPerSample = 16;
                    }
                }

                // Determine format string from MIME type
                String mime = format.getString(MediaFormat.KEY_MIME);
                String audioFormat = mimeToFormat(mime);

                // Fall back to file extension if MIME didn't map
                if (audioFormat == null) {
                    audioFormat = extensionFromPath(path);
                }
                if (audioFormat == null) {
                    audioFormat = "wav";
                }

                JSObject result = new JSObject();
                result.put("sample_rate", sampleRate);
                result.put("channels", channels);
                result.put("bits_per_sample", bitsPerSample);
                result.put("format", audioFormat);

                runOnMain(() -> callback.onResult(Result.success(result)));
            } catch (Exception e) {
                Log.e(TAG, "getAudioFormat", e);
                runOnMain(() -> callback.onResult(Result.error(e)));
            } finally {
                extractor.release();
            }
        });
    }

    private static String mimeToFormat(String mime) {
        if (mime == null) return null;
        switch (mime) {
            case "audio/mpeg":
                return "mp3";
            case "audio/mp4":
            case "audio/aac":
                return "m4a";
            case "audio/ogg":
            case "audio/vorbis":
                return "ogg";
            case "audio/flac":
                return "flac";
            case "audio/x-wav":
            case "audio/wav":
            case "audio/raw":
                return "wav";
            case "audio/webm":
                return "webm";
            default:
                return null;
        }
    }

    private static String extensionFromPath(String path) {
        if (path == null) return null;
        int dot = path.lastIndexOf('.');
        if (dot < 0 || dot == path.length() - 1) return null;
        return path.substring(dot + 1).toLowerCase();
    }

    // ---- Audio decoding (non-WAV formats) ----

    /**
     * Decodes any Android-supported audio format to raw 16kHz mono float32 PCM
     * using MediaExtractor + MediaCodec.
     */
    private static float[] decodeAudioFile(String path) throws Exception {
        MediaExtractor extractor = new MediaExtractor();
        MediaCodec codec = null;
        try {
            extractor.setDataSource(path);

            // Find first audio track
            int audioTrack = -1;
            String mime = null;
            MediaFormat format = null;
            for (int i = 0; i < extractor.getTrackCount(); i++) {
                MediaFormat trackFormat = extractor.getTrackFormat(i);
                String trackMime = trackFormat.getString(MediaFormat.KEY_MIME);
                if (trackMime != null && trackMime.startsWith("audio/")) {
                    audioTrack = i;
                    mime = trackMime;
                    format = trackFormat;
                    break;
                }
            }

            if (audioTrack < 0 || mime == null || format == null) {
                throw new Exception("No audio track found in file: " + path);
            }

            extractor.selectTrack(audioTrack);

            int sourceSampleRate = format.getInteger(MediaFormat.KEY_SAMPLE_RATE);
            int sourceChannels = format.getInteger(MediaFormat.KEY_CHANNEL_COUNT);

            codec = MediaCodec.createDecoderByType(mime);
            codec.configure(format, null, null, 0);
            codec.start();

            MediaCodec.BufferInfo bufferInfo = new MediaCodec.BufferInfo();
            boolean inputDone = false;
            boolean outputDone = false;
            List<float[]> decodedChunks = new ArrayList<>();
            int totalSamples = 0;
            long timeoutUs = 10000; // 10ms

            while (!outputDone) {
                // Feed input buffers
                if (!inputDone) {
                    int inputIndex = codec.dequeueInputBuffer(timeoutUs);
                    if (inputIndex >= 0) {
                        ByteBuffer inputBuffer = codec.getInputBuffer(inputIndex);
                        if (inputBuffer != null) {
                            int sampleSize = extractor.readSampleData(inputBuffer, 0);
                            if (sampleSize < 0) {
                                codec.queueInputBuffer(inputIndex, 0, 0, 0,
                                        MediaCodec.BUFFER_FLAG_END_OF_STREAM);
                                inputDone = true;
                            } else {
                                long presentationTimeUs = extractor.getSampleTime();
                                codec.queueInputBuffer(inputIndex, 0, sampleSize,
                                        presentationTimeUs, 0);
                                extractor.advance();
                            }
                        }
                    }
                }

                // Drain output buffers
                int outputIndex = codec.dequeueOutputBuffer(bufferInfo, timeoutUs);
                if (outputIndex >= 0) {
                    if ((bufferInfo.flags & MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0) {
                        outputDone = true;
                    }

                    ByteBuffer outputBuffer = codec.getOutputBuffer(outputIndex);
                    if (outputBuffer != null && bufferInfo.size > 0) {
                        outputBuffer.position(bufferInfo.offset);
                        outputBuffer.limit(bufferInfo.offset + bufferInfo.size);

                        // Check output format for PCM encoding
                        MediaFormat outputFormat = codec.getOutputFormat();
                        int pcmEncoding = AudioFormat.ENCODING_PCM_16BIT;
                        if (outputFormat.containsKey(MediaFormat.KEY_PCM_ENCODING)) {
                            pcmEncoding = outputFormat.getInteger(MediaFormat.KEY_PCM_ENCODING);
                        }

                        float[] chunk;
                        if (pcmEncoding == AudioFormat.ENCODING_PCM_FLOAT) {
                            // Float32 output
                            int floatCount = bufferInfo.size / 4;
                            chunk = new float[floatCount];
                            outputBuffer.order(ByteOrder.LITTLE_ENDIAN);
                            outputBuffer.asFloatBuffer().get(chunk);
                        } else {
                            // Default: PCM 16-bit output
                            int shortCount = bufferInfo.size / 2;
                            short[] shorts = new short[shortCount];
                            outputBuffer.order(ByteOrder.LITTLE_ENDIAN);
                            outputBuffer.asShortBuffer().get(shorts);
                            chunk = new float[shortCount];
                            for (int i = 0; i < shortCount; i++) {
                                chunk[i] = shorts[i] / 32768.0f;
                            }
                        }

                        decodedChunks.add(chunk);
                        totalSamples += chunk.length;
                    }

                    codec.releaseOutputBuffer(outputIndex, false);
                }
            }

            // Combine all decoded chunks
            float[] allSamples = new float[totalSamples];
            int offset = 0;
            for (float[] chunk : decodedChunks) {
                System.arraycopy(chunk, 0, allSamples, offset, chunk.length);
                offset += chunk.length;
            }

            // Downmix to mono if stereo
            if (sourceChannels > 1) {
                int monoLen = allSamples.length / sourceChannels;
                float[] mono = new float[monoLen];
                for (int i = 0; i < monoLen; i++) {
                    float sum = 0;
                    for (int ch = 0; ch < sourceChannels; ch++) {
                        sum += allSamples[i * sourceChannels + ch];
                    }
                    mono[i] = sum / sourceChannels;
                }
                allSamples = mono;
            }

            // Resample to 16kHz if needed
            allSamples = resample(allSamples, sourceSampleRate, SAMPLE_RATE);

            return allSamples;
        } finally {
            if (codec != null) {
                try { codec.stop(); } catch (Exception ignored) { /* codec cleanup */ }
                try { codec.release(); } catch (Exception ignored) { /* codec cleanup */ }
            }
            extractor.release();
        }
    }

    /**
     * Linear interpolation resampling from sourceSR to targetSR.
     */
    private static float[] resample(float[] input, int sourceSR, int targetSR) {
        if (sourceSR == targetSR) return input;
        double ratio = (double) sourceSR / targetSR;
        int outLen = (int) (input.length / ratio);
        if (outLen <= 0) return new float[0];
        float[] output = new float[outLen];
        for (int i = 0; i < outLen; i++) {
            double srcIdx = i * ratio;
            int idx0 = (int) srcIdx;
            float frac = (float) (srcIdx - idx0);
            int idx1 = Math.min(idx0 + 1, input.length - 1);
            output[i] = input[idx0] * (1 - frac) + input[idx1] * frac;
        }
        return output;
    }

    /**
     * Encodes a float[] as little-endian base64 for passing to JNI as raw PCM.
     */
    private static String floatArrayToBase64(float[] samples) {
        ByteBuffer buf = ByteBuffer.allocate(samples.length * 4);
        buf.order(ByteOrder.LITTLE_ENDIAN);
        for (float s : samples) {
            buf.putFloat(s);
        }
        return Base64.encodeToString(buf.array(), Base64.NO_WRAP);
    }

    // ---- Streaming transcription ----

    public void transcribeRealtime(JSObject params, SegmentCallback onSegment, ResultCallback<JSObject> onResult, ErrorCallback onError) {
        synchronized (sessionLock) {
            if (activeSession != null) {
                runOnMain(() -> onError.onError("A streaming session is already active"));
                return;
            }
        }

        // Check microphone permission
        if (context.checkSelfPermission(Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
            runOnMain(() -> onError.onError("Microphone permission denied"));
            return;
        }

        int contextId = params != null ? params.optInt("contextId", 0) : 0;
        if (contextId == 0) {
            runOnMain(() -> onError.onError("contextId is required for transcribeRealtime"));
            return;
        }

        int chunkLengthMs = params.optInt("chunk_length_ms", 3000);
        int stepLengthMs = params.optInt("step_length_ms", 500);

        StreamingSession session = new StreamingSession(
            contextId, chunkLengthMs, stepLengthMs,
            params, onSegment, onResult, onError
        );

        synchronized (sessionLock) {
            if (activeSession != null) {
                runOnMain(() -> onError.onError("A streaming session is already active"));
                return;
            }
            activeSession = session;
        }

        try {
            session.start();
        } catch (Exception e) {
            synchronized (sessionLock) {
                activeSession = null;
            }
            runOnMain(() -> onError.onError("Failed to start audio recording: " + e.getMessage()));
        }
    }

    public void stopTranscription(ResultCallback<Void> callback) {
        StreamingSession session;
        synchronized (sessionLock) {
            session = activeSession;
        }

        if (session == null) {
            runOnMain(() -> callback.onResult(Result.success(null)));
            return;
        }

        // Stop runs on executor to avoid blocking the main thread
        executor.execute(() -> {
            session.stop();
            // activeSession is cleared in the session's onResult callback
            runOnMain(() -> callback.onResult(Result.success(null)));
        });
    }

    // ---- StreamingSession inner class ----

    private class StreamingSession {
        private final int contextId;
        private final int chunkLengthMs;
        private final int stepLengthMs;
        private final JSObject params;
        private final SegmentCallback onSegment;
        private final ResultCallback<JSObject> onResult;
        private final ErrorCallback onError;

        private AudioRecord audioRecord;
        private volatile boolean isActive = false;
        private Thread recordingThread;
        private Thread processingThread;

        // Audio buffer with synchronization
        private final Object bufferLock = new Object();
        private final List<float[]> pendingChunks = new ArrayList<>();
        private float[] sampleBuffer = new float[0];

        // Accumulated results
        private final List<JSObject> allSegments = new ArrayList<>();
        private final StringBuilder fullText = new StringBuilder();
        private double lastEndTime = 0;
        private long totalSamplesProcessed = 0;

        StreamingSession(int contextId, int chunkLengthMs, int stepLengthMs,
                         JSObject params, SegmentCallback onSegment,
                         ResultCallback<JSObject> onResult, ErrorCallback onError) {
            this.contextId = contextId;
            this.chunkLengthMs = chunkLengthMs;
            this.stepLengthMs = stepLengthMs;
            this.params = params;
            this.onSegment = onSegment;
            this.onResult = onResult;
            this.onError = onError;
        }

        void start() {
            int chunkSamples = (int) (SAMPLE_RATE * chunkLengthMs / 1000.0);

            // Determine encoding: prefer PCM_FLOAT, fall back to PCM_16BIT
            int encoding = AudioFormat.ENCODING_PCM_FLOAT;
            int minBufSize = AudioRecord.getMinBufferSize(
                SAMPLE_RATE, AudioFormat.CHANNEL_IN_MONO, encoding
            );
            boolean useFloat = minBufSize > 0;

            if (!useFloat) {
                encoding = AudioFormat.ENCODING_PCM_16BIT;
                minBufSize = AudioRecord.getMinBufferSize(
                    SAMPLE_RATE, AudioFormat.CHANNEL_IN_MONO, encoding
                );
            }

            if (minBufSize <= 0) {
                throw new RuntimeException("AudioRecord not supported with 16kHz mono");
            }

            // Use a buffer large enough for smooth recording
            int bufferSize = Math.max(minBufSize, chunkSamples * (useFloat ? 4 : 2));

            audioRecord = new AudioRecord(
                MediaRecorder.AudioSource.MIC,
                SAMPLE_RATE,
                AudioFormat.CHANNEL_IN_MONO,
                encoding,
                bufferSize
            );

            if (audioRecord.getState() != AudioRecord.STATE_INITIALIZED) {
                audioRecord.release();
                audioRecord = null;
                throw new RuntimeException("AudioRecord failed to initialize");
            }

            isActive = true;
            audioRecord.startRecording();

            final boolean finalUseFloat = useFloat;

            // Recording thread: reads from AudioRecord into sampleBuffer
            recordingThread = new Thread(() -> {
                if (finalUseFloat) {
                    readFloatLoop();
                } else {
                    readShortLoop();
                }
            }, "WhisperRecording");
            recordingThread.start();

            // Processing thread: processes chunks when buffer is large enough
            processingThread = new Thread(() -> processLoop(chunkSamples), "WhisperProcessing");
            processingThread.start();
        }

        private void readFloatLoop() {
            float[] readBuf = new float[1024];
            while (isActive) {
                int read = audioRecord.read(readBuf, 0, readBuf.length, AudioRecord.READ_BLOCKING);
                if (read > 0) {
                    float[] samples = new float[read];
                    System.arraycopy(readBuf, 0, samples, 0, read);
                    synchronized (bufferLock) {
                        appendToBuffer(samples);
                        bufferLock.notifyAll();
                    }
                }
            }
        }

        private void readShortLoop() {
            short[] readBuf = new short[1024];
            while (isActive) {
                int read = audioRecord.read(readBuf, 0, readBuf.length);
                if (read > 0) {
                    float[] samples = new float[read];
                    for (int i = 0; i < read; i++) {
                        samples[i] = readBuf[i] / 32768.0f;
                    }
                    synchronized (bufferLock) {
                        appendToBuffer(samples);
                        bufferLock.notifyAll();
                    }
                }
            }
        }

        private void appendToBuffer(float[] newSamples) {
            float[] combined = new float[sampleBuffer.length + newSamples.length];
            System.arraycopy(sampleBuffer, 0, combined, 0, sampleBuffer.length);
            System.arraycopy(newSamples, 0, combined, sampleBuffer.length, newSamples.length);
            sampleBuffer = combined;
        }

        private void processLoop(int chunkSamples) {
            int stepSamples = (int) (SAMPLE_RATE * stepLengthMs / 1000.0);

            while (isActive) {
                float[] chunk = null;
                synchronized (bufferLock) {
                    while (isActive && sampleBuffer.length < chunkSamples) {
                        try {
                            bufferLock.wait(100);
                        } catch (InterruptedException e) {
                            return;
                        }
                    }
                    if (!isActive) break;

                    if (sampleBuffer.length >= chunkSamples) {
                        chunk = new float[chunkSamples];
                        System.arraycopy(sampleBuffer, 0, chunk, 0, chunkSamples);

                        // Slide window: remove (chunkSamples - stepSamples) from front
                        int removeCount = Math.max(chunkSamples - stepSamples, 0);
                        if (removeCount > 0 && removeCount <= sampleBuffer.length) {
                            int remaining = sampleBuffer.length - removeCount;
                            float[] newBuf = new float[remaining];
                            System.arraycopy(sampleBuffer, removeCount, newBuf, 0, remaining);
                            sampleBuffer = newBuf;
                        }
                    }
                }

                if (chunk != null) {
                    processChunk(chunk, chunkSamples, stepSamples);
                }
            }
        }

        private void processChunk(float[] chunk, int chunkSamples, int stepSamples) {
            // Calculate time offset for this chunk
            long chunkOffsetMs = (long) (totalSamplesProcessed * 1000.0 / SAMPLE_RATE);
            totalSamplesProcessed += Math.max(chunkSamples - stepSamples, 0);

            // Encode float[] as base64 for NativeBridge.transcribe
            String base64Audio = floatArrayToBase64(chunk);

            try {
                String resultJson = NativeBridge.transcribe(
                    contextId, base64Audio, false,
                    params != null ? params.toString() : "{}"
                );

                if (resultJson == null || resultJson.isEmpty() || resultJson.equals("{}")) {
                    return;
                }

                JSONObject result = new JSONObject(resultJson);
                JSONArray segments = result.optJSONArray("segments");
                if (segments == null) return;

                for (int i = 0; i < segments.length(); i++) {
                    JSONObject seg = segments.getJSONObject(i);

                    // Adjust timestamps relative to overall stream
                    double start = seg.optDouble("start", 0) + chunkOffsetMs;
                    double end = seg.optDouble("end", 0) + chunkOffsetMs;

                    // Ensure monotonic: start >= last end
                    if (start < lastEndTime) {
                        start = lastEndTime;
                    }
                    if (end < start) {
                        end = start;
                    }
                    lastEndTime = end;

                    String text = seg.optString("text", "");

                    JSObject segObj = new JSObject();
                    segObj.put("start", start);
                    segObj.put("end", end);
                    segObj.put("text", text);
                    segObj.put("no_speech_prob", seg.optDouble("no_speech_prob", 0));
                    segObj.put("speaker_id", seg.optInt("speaker_id", 0));

                    fullText.append(text);
                    allSegments.add(segObj);

                    // Emit segment event on main thread
                    final JSObject emitSeg = segObj;
                    runOnMain(() -> onSegment.onSegment(emitSeg));
                }
            } catch (Exception e) {
                Log.e(TAG, "processChunk error", e);
                final String msg = e.getMessage();
                runOnMain(() -> onError.onError("Chunk processing error: " + msg));
            }
        }

        void stop() {
            if (!isActive) return;
            isActive = false;

            // Stop audio recording
            if (audioRecord != null) {
                try {
                    audioRecord.stop();
                } catch (Exception e) {
                    Log.w(TAG, "AudioRecord stop error", e);
                }
                audioRecord.release();
                audioRecord = null;
            }

            // Wake up processing thread
            synchronized (bufferLock) {
                bufferLock.notifyAll();
            }

            // Wait for threads to finish
            try {
                if (recordingThread != null) recordingThread.join(2000);
                if (processingThread != null) processingThread.join(2000);
            } catch (InterruptedException e) {
                Log.w(TAG, "Thread join interrupted", e);
            }

            // Process remaining buffered audio
            float[] remaining;
            synchronized (bufferLock) {
                remaining = sampleBuffer;
                sampleBuffer = new float[0];
            }

            if (remaining.length > 0) {
                processRemainingAudio(remaining);
            }

            // Emit final result
            emitFinalResult();
        }

        private void processRemainingAudio(float[] samples) {
            long chunkOffsetMs = (long) (totalSamplesProcessed * 1000.0 / SAMPLE_RATE);
            totalSamplesProcessed += samples.length;

            String base64Audio = floatArrayToBase64(samples);

            try {
                String resultJson = NativeBridge.transcribe(
                    contextId, base64Audio, false,
                    params != null ? params.toString() : "{}"
                );

                if (resultJson == null || resultJson.isEmpty() || resultJson.equals("{}")) {
                    return;
                }

                JSONObject result = new JSONObject(resultJson);
                JSONArray segments = result.optJSONArray("segments");
                if (segments == null) return;

                for (int i = 0; i < segments.length(); i++) {
                    JSONObject seg = segments.getJSONObject(i);

                    double start = seg.optDouble("start", 0) + chunkOffsetMs;
                    double end = seg.optDouble("end", 0) + chunkOffsetMs;

                    if (start < lastEndTime) start = lastEndTime;
                    if (end < start) end = start;
                    lastEndTime = end;

                    String text = seg.optString("text", "");

                    JSObject segObj = new JSObject();
                    segObj.put("start", start);
                    segObj.put("end", end);
                    segObj.put("text", text);
                    segObj.put("no_speech_prob", seg.optDouble("no_speech_prob", 0));
                    segObj.put("speaker_id", seg.optInt("speaker_id", 0));

                    fullText.append(text);
                    allSegments.add(segObj);
                    // Don't emit individual segment events during stop
                }
            } catch (Exception e) {
                Log.e(TAG, "processRemainingAudio error", e);
            }
        }

        private void emitFinalResult() {
            try {
                double totalDurationMs = totalSamplesProcessed * 1000.0 / SAMPLE_RATE;

                JSObject finalResult = new JSObject();
                finalResult.put("text", fullText.toString());

                JSONArray segsArray = new JSONArray();
                for (JSObject seg : allSegments) {
                    segsArray.put(seg);
                }
                finalResult.put("segments", segsArray);
                finalResult.put("words", new JSONArray());

                String language = "en";
                if (params != null) {
                    String paramLang = params.optString("language", null);
                    if (paramLang != null && !paramLang.isEmpty()) {
                        language = paramLang;
                    }
                }
                finalResult.put("language", language);
                finalResult.put("language_prob", 1.0);
                finalResult.put("duration_ms", totalDurationMs);
                finalResult.put("processing_time_ms", 0);

                // Clear activeSession before emitting result
                synchronized (sessionLock) {
                    activeSession = null;
                }

                runOnMain(() -> onResult.onResult(Result.success(finalResult)));
            } catch (Exception e) {
                Log.e(TAG, "emitFinalResult error", e);
                synchronized (sessionLock) {
                    activeSession = null;
                }
                final String msg = e.getMessage();
                runOnMain(() -> onError.onError("Failed to emit final result: " + msg));
            }
        }
    }

    // ---- JNI Native Bridge ----

    static class NativeBridge {
        static {
            try {
                System.loadLibrary("whisper-jni");
            } catch (Throwable t) {
                Log.e(TAG, "Failed to load libwhisper-jni", t);
            }
        }
        static native String initContext(String modelPath, String paramsJson);
        static native boolean releaseContext(int contextId);
        static native void releaseAllContexts();
        static native String transcribe(int contextId, String audioData, boolean isAudioFile, String paramsJson);
        static native String transcribeWithProgress(int contextId, String audioData, boolean isAudioFile, String paramsJson, Object progressCallback);
        static native String getSystemInfo();
    }
}
