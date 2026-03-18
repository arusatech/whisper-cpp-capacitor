package com.getcapacitor.plugin.whispercpp;

import android.util.Log;
import com.getcapacitor.JSObject;
import com.getcapacitor.Plugin;
import com.getcapacitor.PluginCall;
import com.getcapacitor.PluginMethod;
import com.getcapacitor.annotation.CapacitorPlugin;
import org.json.JSONException;
import org.json.JSONObject;

@CapacitorPlugin(name = "WhisperCpp")
public class WhisperCppPlugin extends Plugin {
    private static final String TAG = "WhisperCppPlugin";
    private static final String KEY_PARAMS = "params";
    private static final String KEY_MODEL = "model";
    private static final String KEY_CONTEXT_ID = "contextId";
    private WhisperCpp implementation;

    @Override
    public void load() {
        super.load();
        implementation = new WhisperCpp(getContext());
        Log.i(TAG, "WhisperCppPlugin loaded");
    }

    @PluginMethod
    public void initContext(PluginCall call) {
        JSObject params = call.getObject(KEY_PARAMS);
        String model = (params != null && params.has(KEY_MODEL)) ? params.getString(KEY_MODEL) : call.getString(KEY_MODEL);
        if (model == null || model.isEmpty()) {
            call.reject("model path is required");
            return;
        }
        if (params == null) params = new JSObject();
        implementation.initContext(model, params != null ? params : new JSObject(), result -> {
            if (result.isSuccess()) {
                try {
                    call.resolve(result.getData());
                } catch (Exception e) {
                    call.reject(e.getMessage());
                }
            } else {
                call.reject(result.getError().getMessage());
            }
        });
    }

    @PluginMethod
    public void releaseContext(PluginCall call) {
        Integer contextId = call.getInt(KEY_CONTEXT_ID);
        if (contextId == null) {
            call.reject("contextId is required");
            return;
        }
        implementation.releaseContext(contextId, result -> {
            if (result.isSuccess()) call.resolve();
            else call.reject(result.getError().getMessage());
        });
    }

    @PluginMethod
    public void releaseAllContexts(PluginCall call) {
        implementation.releaseAllContexts(result -> {
            if (result.isSuccess()) call.resolve();
            else call.reject(result.getError().getMessage());
        });
    }

    @PluginMethod
    public void transcribe(PluginCall call) {
        String audioData = call.getString("audio_data");
        Boolean isAudioFile = call.getBoolean("is_audio_file", false);
        JSObject params = call.getObject(KEY_PARAMS);
        if (audioData == null || params == null) {
            call.reject("audio_data and params are required");
            return;
        }
        mergeContextId(call, params);

        WhisperCpp.ProgressCallback progressCallback = buildProgressCallback(params);

        implementation.transcribe(audioData, isAudioFile != null && isAudioFile, params, progressCallback, result -> {
            if (result.isSuccess()) {
                try {
                    call.resolve(result.getData());
                } catch (Exception e) {
                    call.reject(e.getMessage());
                }
            } else {
                call.reject(result.getError().getMessage());
            }
        });
    }

    @PluginMethod
    public void transcribeRealtime(PluginCall call) {
        JSObject params = call.getObject(KEY_PARAMS);
        if (params == null) {
            call.reject("params are required");
            return;
        }

        // Merge top-level streaming params into the params object
        Integer chunkLength = call.getInt("chunk_length_ms");
        if (chunkLength != null) {
            try { params.put("chunk_length_ms", chunkLength); } catch (JSONException e) { /* int value, safe */ }
        }
        Integer stepLength = call.getInt("step_length_ms");
        if (stepLength != null) {
            try { params.put("step_length_ms", stepLength); } catch (JSONException e) { /* int value, safe */ }
        }
        // Ensure contextId is available in params
        Integer contextId = call.getInt(KEY_CONTEXT_ID);
        if (contextId != null) {
            try { params.put(KEY_CONTEXT_ID, contextId); } catch (JSONException e) { /* int value, safe */ }
        }

        implementation.transcribeRealtime(
            params,
            segment -> notifyListeners("segment", segment),
            result -> {
                if (result.isSuccess()) {
                    notifyListeners("transcribeResult", result.getData());
                }
            },
            message -> {
                JSObject errorData = new JSObject();
                try { errorData.put("message", message); } catch (JSONException e) { /* string value, safe */ }
                notifyListeners("error", errorData);
            }
        );

        // Resolve immediately — streaming results come via events
        call.resolve();
    }

    private void mergeContextId(PluginCall call, JSObject params) {
        Integer contextId = call.getInt(KEY_CONTEXT_ID);
        if (contextId != null) {
            try {
                params.put(KEY_CONTEXT_ID, contextId);
            } catch (JSONException e) { /* primitive int, put won't fail */ }
        }
    }

    private WhisperCpp.ProgressCallback buildProgressCallback(JSObject params) {
        if (!params.optBoolean("use_progress_callback", false)) {
            return null;
        }
        return progress -> {
            JSObject data = new JSObject();
            try {
                data.put("progress", progress);
            } catch (JSONException e) { /* primitive int, put won't fail */ }
            new android.os.Handler(android.os.Looper.getMainLooper()).post(() ->
                notifyListeners("progress", data)
            );
        };
    }

    @PluginMethod
    public void stopTranscription(PluginCall call) {
        implementation.stopTranscription(result -> {
            if (result.isSuccess()) {
                call.resolve();
            } else {
                call.reject(result.getError().getMessage());
            }
        });
    }

    @PluginMethod
    public void getSystemInfo(PluginCall call) {
        implementation.getSystemInfo(result -> {
            if (result.isSuccess()) {
                try {
                    call.resolve(result.getData());
                } catch (Exception e) {
                    call.reject(e.getMessage());
                }
            } else {
                call.reject(result.getError().getMessage());
            }
        });
    }

    @PluginMethod
    public void getModelInfo(PluginCall call) {
        call.reject("getModelInfo: use initContext result model info");
    }

    @PluginMethod
    public void loadModel(PluginCall call) {
        call.resolve();
    }

    @PluginMethod
    public void unloadModel(PluginCall call) {
        implementation.releaseAllContexts(result -> call.resolve());
    }

    @PluginMethod
    public void getAudioFormat(PluginCall call) {
        String path = call.getString("path");
        if (path == null || path.isEmpty()) {
            call.reject("path is required");
            return;
        }
        implementation.getAudioFormat(path, result -> {
            if (result.isSuccess()) {
                call.resolve(result.getData());
            } else {
                call.reject(result.getError().getMessage());
            }
        });
    }

    @PluginMethod
    public void convertAudio(PluginCall call) {
        call.reject("convertAudio not implemented");
    }

    @PluginMethod
    public void addListener(PluginCall call) {
        call.resolve();
    }

    @PluginMethod
    public void removeAllListeners(PluginCall call) {
        call.resolve();
    }
}
