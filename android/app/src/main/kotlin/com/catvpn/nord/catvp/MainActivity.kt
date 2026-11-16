package com.catvpn.nord.catvp

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.VpnService
import android.os.Handler
import android.os.Looper
import com.wireguard.android.backend.GoBackend
import com.wireguard.android.backend.Tunnel
import com.wireguard.config.Config
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.BufferedReader
import java.io.StringReader
import java.util.concurrent.Executors

class CatWgTunnel(private val tunnelName: String = "catvpn") : Tunnel {
    @Volatile
    var currentState: Tunnel.State = Tunnel.State.DOWN

    override fun getName(): String = tunnelName

    override fun onStateChange(newState: Tunnel.State) {
        currentState = newState
    }
}

object VpnRuntimeHolder {
    @Volatile
    private var backendInstance: GoBackend? = null
    val tunnel = CatWgTunnel("catvpn")
    val executor = Executors.newSingleThreadExecutor()

    fun getBackend(context: Context): GoBackend {
        return backendInstance ?: synchronized(this) {
            backendInstance ?: GoBackend(context.applicationContext).also {
                backendInstance = it
            }
        }
    }
}

class MainActivity : FlutterActivity() {
    private val channelName = "com.catvpn.nord/vpn"
    private val reqCodeVpnPermission = 7001
    private var pendingPermissionResult: MethodChannel.Result? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "prepareVpn" -> {
                        val intent = VpnService.prepare(this)
                        if (intent != null) {
                            pendingPermissionResult = result
                            startActivityForResult(intent, reqCodeVpnPermission)
                        } else {
                            result.success(true)
                        }
                    }

                    "connect" -> {
                        val wgConfig = call.argument<String>("config")
                        if (wgConfig.isNullOrBlank()) {
                            result.error("INVALID_CONFIG", "WireGuard config is empty", null)
                            return@setMethodCallHandler
                        }
                        val prepIntent = VpnService.prepare(this)
                        if (prepIntent != null) {
                            result.error("VPN_PERMISSION_REQUIRED", "VPN permission not granted", null)
                            return@setMethodCallHandler
                        }

                        val appCtx = applicationContext
                        VpnRuntimeHolder.executor.execute {
                            try {
                                val backend = VpnRuntimeHolder.getBackend(appCtx)
                                val tunnel = VpnRuntimeHolder.tunnel
                                if (backend.runningTunnelNames.contains(tunnel.name) ||
                                    backend.getState(tunnel) == Tunnel.State.UP
                                ) {
                                    backend.setState(tunnel, Tunnel.State.DOWN, null)
                                    Thread.sleep(150)
                                }
                                val parsedConfig = Config.parse(BufferedReader(StringReader(wgConfig)))
                                val newState = backend.setState(tunnel, Tunnel.State.UP, parsedConfig)
                                mainHandler.post {
                                    result.success(newState.name)
                                }
                            } catch (e: Exception) {
                                mainHandler.post {
                                    result.error("CONNECT_FAILED", e.message ?: e.toString(), null)
                                }
                            }
                        }
                    }

                    "disconnect" -> {
                        val appCtx = applicationContext
                        VpnRuntimeHolder.executor.execute {
                            try {
                                val backend = VpnRuntimeHolder.getBackend(appCtx)
                                val tunnel = VpnRuntimeHolder.tunnel
                                val newState = backend.setState(tunnel, Tunnel.State.DOWN, null)
                                mainHandler.post {
                                    result.success(newState.name)
                                }
                            } catch (e: Exception) {
                                mainHandler.post {
                                    result.error("DISCONNECT_FAILED", e.message ?: e.toString(), null)
                                }
                            }
                        }
                    }

                    "getStatus" -> {
                        val appCtx = applicationContext
                        VpnRuntimeHolder.executor.execute {
                            try {
                                val backend = VpnRuntimeHolder.getBackend(appCtx)
                                val tunnel = VpnRuntimeHolder.tunnel
                                val backendUp = backend.runningTunnelNames.contains(tunnel.name) ||
                                    backend.getState(tunnel) == Tunnel.State.UP

                                val cm = appCtx.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
                                val osVpnActive = cm.allNetworks.any { net ->
                                    cm.getNetworkCapabilities(net)
                                        ?.hasTransport(NetworkCapabilities.TRANSPORT_VPN) == true
                                }

                                var revokedExternally = false
                                var isRunning = backendUp && osVpnActive
                                if (backendUp && !osVpnActive) {
                                    revokedExternally = true
                                    try {
                                        backend.setState(tunnel, Tunnel.State.DOWN, null)
                                    } catch (_: Exception) {}
                                    isRunning = false
                                }

                                var rxBytes = 0L
                                var txBytes = 0L
                                if (isRunning) {
                                    val stats = backend.getStatistics(tunnel)
                                    rxBytes = stats.totalRx()
                                    txBytes = stats.totalTx()
                                }
                                val payload = mapOf(
                                    "state" to if (isRunning) "UP" else "DOWN",
                                    "rxBytes" to rxBytes,
                                    "txBytes" to txBytes,
                                    "revoked" to revokedExternally
                                )
                                mainHandler.post {
                                    result.success(payload)
                                }
                            } catch (e: Exception) {
                                mainHandler.post {
                                    result.success(
                                        mapOf(
                                            "state" to "DOWN",
                                            "rxBytes" to 0L,
                                            "txBytes" to 0L,
                                            "revoked" to false
                                        )
                                    )
                                }
                            }
                        }
                    }

                    "savePref" -> {
                        val key = call.argument<String>("key") ?: ""
                        val value = call.argument<String>("value") ?: ""
                        val prefs = getSharedPreferences("catvpn_prefs", Context.MODE_PRIVATE)
                        prefs.edit().putString(key, value).apply()
                        result.success(true)
                    }

                    "loadPrefs" -> {
                        val prefs = getSharedPreferences("catvpn_prefs", Context.MODE_PRIVATE)
                        val allStrings = mutableMapOf<String, String>()
                        for ((k, v) in prefs.all) {
                            if (v is String) {
                                allStrings[k] = v
                            }
                        }
                        result.success(allStrings)
                    }

                    else -> result.notImplemented()
                }
            }
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == reqCodeVpnPermission) {
            val res = pendingPermissionResult
            pendingPermissionResult = null
            res?.success(resultCode == Activity.RESULT_OK)
        }
    }
}
