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
    private WhisperCpp implementation;

    @Override
    public void load() {
        super.load();
        implementation = new WhisperCpp(getContext());
        Log.i(TAG, "WhisperCppPlugin loaded");
    }

    @PluginMethod
    public void initContext(PluginCall call) {
        JSObject params = call.getObject("params");
        String model = (params != null && params.has("model")) ? params.getString("model") : call.getString("model");
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
        Integer contextId = call.getInt("contextId");
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
        JSObject params = call.getObject("params");
        if (audioData == null || params == null) {
            call.reject("audio_data and params are required");
            return;
        }
        Integer contextId = call.getInt("contextId");
        if (contextId != null) {
            try {
                params.put("contextId", contextId);
            } catch (JSONException ignored) {}
        }
        implementation.transcribe(audioData, isAudioFile != null && isAudioFile, params, result -> {
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
        call.reject("transcribeRealtime not implemented on Android yet");
    }

    @PluginMethod
    public void stopTranscription(PluginCall call) {
        call.resolve();
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
        call.reject("getAudioFormat not implemented");
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
