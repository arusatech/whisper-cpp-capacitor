package com.getcapacitor.plugin.whispercpp;

import android.content.Context;
import android.os.Handler;
import android.os.Looper;
import android.util.Log;
import com.getcapacitor.JSObject;
import org.json.JSONException;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

public class WhisperCpp {
    private static final String TAG = "WhisperCpp";
    private final Context context;
    private final ExecutorService executor = Executors.newSingleThreadExecutor();
    private final Handler mainHandler = new Handler(Looper.getMainLooper());

    public WhisperCpp(Context context) {
        this.context = context.getApplicationContext();
    }

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
        int contextId = (params != null && params.has("contextId")) ? params.optInt("contextId", 0) : 0;
        executor.execute(() -> {
            try {
                String json = NativeBridge.transcribe(contextId, audioData, isAudioFile, params != null ? params.toString() : "{}");
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

    public interface ResultCallback<T> {
        void onResult(Result<T> result);
    }

    public static class Result<T> {
        final T data;
        final Error error;
        private Result(T data, Error error) {
            this.data = data;
            this.error = error;
        }
        public static <T> Result<T> success(T data) { return new Result<>(data, null); }
        public static <T> Result<T> error(Error e) { return new Result<>(null, e); }
        public boolean isSuccess() { return error == null; }
        public T getData() { return data; }
        public Error getError() { return error; }
    }

    private static class NativeBridge {
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
        static native String getSystemInfo();
    }
}
