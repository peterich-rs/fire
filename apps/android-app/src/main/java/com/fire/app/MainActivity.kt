package com.fire.app

import android.os.Bundle
import android.view.View
import androidx.appcompat.app.AppCompatActivity
import androidx.activity.enableEdgeToEdge
import androidx.core.view.ViewCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.updatePadding
import androidx.lifecycle.DefaultLifecycleObserver
import androidx.lifecycle.LifecycleOwner
import androidx.lifecycle.ProcessLifecycleOwner
import androidx.appcompat.app.AlertDialog
import androidx.lifecycle.lifecycleScope
import androidx.navigation.NavController
import androidx.navigation.NavOptions
import androidx.navigation.fragment.NavHostFragment
import com.fire.app.databinding.ActivityMainBinding
import com.fire.app.session.FireBrowserTransportPrompt
import com.fire.app.session.FireSessionRecoveryPolicy
import com.fire.app.session.FireCfClearanceRefreshService
import com.fire.app.session.FireSessionStoreRepository
import com.fire.app.session.FireStateObserverRepository
import com.fire.app.session.FireWebViewCookieActionSupport
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import uniffi.fire_uniffi_session.SessionState

class MainActivity : AppCompatActivity() {

    private lateinit var binding: ActivityMainBinding
    private var hasLatchedAskEnableBrowserTransport = false
    private var isAskEnableDialogVisible = false
    private var latestSessionSnapshot: SessionState? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        enableEdgeToEdge()
        super.onCreate(savedInstanceState)
        binding = ActivityMainBinding.inflate(layoutInflater)
        setContentView(binding.root)
        applySystemBarInsets()

        val navHostFragment = supportFragmentManager
            .findFragmentById(R.id.nav_host_fragment) as NavHostFragment
        val navController = navHostFragment.navController

        configureBottomNavigation(navController)
        handleWidgetDeepLink(navController)
        bindCloudflareRefreshLifecycle()
        bindSessionExpiryObserver(navController)

        refreshNotificationBadge()
    }

    private fun bindCloudflareRefreshLifecycle() {
        ProcessLifecycleOwner.get().lifecycle.addObserver(object : DefaultLifecycleObserver {
            override fun onStart(owner: LifecycleOwner) {
                FireCfClearanceRefreshService.get(this@MainActivity).setSceneActive(true)
                lifecycleScope.launch {
                    runCatching {
                        FireSessionStoreRepository.get(this@MainActivity).noteAppForegrounded()
                    }
                    presentAskEnableBrowserTransportIfNeeded(latestSessionSnapshot)
                }
            }

            override fun onStop(owner: LifecycleOwner) {
                FireCfClearanceRefreshService.get(this@MainActivity).setSceneActive(false)
                lifecycleScope.launch {
                    runCatching {
                        FireSessionStoreRepository.get(this@MainActivity).noteAppBackgrounded()
                    }
                }
            }
        })
        lifecycleScope.launch {
            val store = FireSessionStoreRepository.get(this@MainActivity)
            val refresh = FireCfClearanceRefreshService.get(this@MainActivity)
            refresh.bind(store)
            val snapshot = withContext(Dispatchers.IO) { store.snapshot() }
            refresh.updateSession(snapshot)
            if (snapshot.readiness.hasCurrentUser && snapshot.readiness.canReadAuthenticatedApi) {
                refresh.setLoginStateConfirmed(true)
            }
        }
    }

    private fun configureBottomNavigation(navController: NavController) {
        binding.bottomNav.setOnItemSelectedListener { item ->
            val destinationId = item.itemId
            if (navController.currentDestination?.id == destinationId) {
                return@setOnItemSelectedListener true
            }

            val tabOptions = NavOptions.Builder()
                .setLaunchSingleTop(true)
                .setRestoreState(true)
                .setPopUpTo(R.id.homeFragment, false, true)
                .build()

            runCatching {
                navController.navigate(destinationId, null, tabOptions)
            }.recoverCatching {
                navController.navigate(destinationId)
            }.isSuccess
        }

        navController.addOnDestinationChangedListener { _, destination, _ ->
            binding.bottomNav.visibility =
                if (destination.id in bottomTabDestinations) View.VISIBLE else View.GONE

            if (destination.id in bottomTabDestinations) {
                binding.bottomNav.menu.findItem(destination.id)?.isChecked = true
            }
        }

        handleSignedOutLaunch(navController)
    }

    private fun handleWidgetDeepLink(navController: NavController) {
        val uri = intent?.data ?: return
        if (uri.scheme != "fire") return
        when (uri.host) {
            "notifications" -> {
                navController.navigate(R.id.notificationsFragment)
                binding.bottomNav.menu.findItem(R.id.notificationsFragment)?.isChecked = true
            }
            "profile" -> {
                val username = uri.pathSegments.firstOrNull()
                    ?: uri.lastPathSegment
                    ?: return
                navController.navigate(
                    R.id.profileFragment,
                    androidx.core.os.bundleOf("username" to username),
                )
            }
            else -> return
        }
    }

    fun refreshNotificationBadge() {
        lifecycleScope.launch {
            val sessionStore = FireSessionStoreRepository.get(this@MainActivity)
            val state = withContext(Dispatchers.IO) {
                runCatching { sessionStore.notificationState() }.getOrNull()
            }
            val unreadCount = state?.counters?.allUnread?.toInt() ?: 0
            val badge = binding.bottomNav.getOrCreateBadge(R.id.notificationsFragment)
            if (unreadCount > 0) {
                badge.number = unreadCount
                badge.isVisible = true
            } else {
                badge.isVisible = false
            }
        }
    }

    fun updateChatBadge(unreadCount: Int) {
        val badge = binding.bottomNav.getOrCreateBadge(R.id.chatFragment)
        if (unreadCount > 0) {
            badge.number = unreadCount
            badge.isVisible = true
        } else {
            badge.isVisible = false
        }
    }

    private fun applySystemBarInsets() {
        val root = binding.root
        val initialLeft = root.paddingLeft
        val initialTop = root.paddingTop
        val initialRight = root.paddingRight
        val initialBottom = root.paddingBottom
        ViewCompat.setOnApplyWindowInsetsListener(root) { view, insets ->
            val systemBars = insets.getInsets(WindowInsetsCompat.Type.systemBars())
            view.updatePadding(
                left = initialLeft + systemBars.left,
                top = initialTop + systemBars.top,
                right = initialRight + systemBars.right,
                bottom = initialBottom + systemBars.bottom,
            )
            insets
        }
        ViewCompat.requestApplyInsets(root)
    }

    private fun bindSessionExpiryObserver(navController: NavController) {
        lifecycleScope.launch {
            var wasAuthenticated = withContext(Dispatchers.IO) {
                runCatching {
                    FireSessionStoreRepository.get(this@MainActivity).snapshot()
                        .readiness.canReadAuthenticatedApi
                }.getOrDefault(false)
            }
            FireStateObserverRepository.sessionSnapshots.collect { snapshot ->
                latestSessionSnapshot = snapshot
                val suppressLoginRecovery = FireSessionRecoveryPolicy.suppressesHostLoginRecovery(
                    snapshot.recovery,
                )
                if (!suppressLoginRecovery) {
                    presentAskEnableBrowserTransportIfNeeded(snapshot)
                }
                val isAuthenticated = snapshot.readiness.canReadAuthenticatedApi
                if (!suppressLoginRecovery && wasAuthenticated && !isAuthenticated) {
                    FireWebViewCookieActionSupport.clearIdentityCookies()
                    if (navController.currentDestination?.id != R.id.onboardingFragment) {
                        val options = NavOptions.Builder()
                            .setPopUpTo(R.id.fire_nav_graph, true)
                            .build()
                        runCatching {
                            navController.navigate(
                                R.id.onboardingFragment,
                                androidx.core.os.bundleOf("onboardingEntry" to "sessionExpired"),
                                options,
                            )
                        }
                    }
                }
                wasAuthenticated = isAuthenticated
            }
        }
    }

    private fun presentAskEnableBrowserTransportIfNeeded(snapshot: SessionState?) {
        val kind = snapshot?.let(FireBrowserTransportPrompt::signalKind)
        if (!FireBrowserTransportPrompt.shouldPresent(kind, hasLatchedAskEnableBrowserTransport)) {
            hasLatchedAskEnableBrowserTransport = FireBrowserTransportPrompt.nextLatch(kind)
            return
        }
        if (isFinishing || isDestroyed || !lifecycle.currentState.isAtLeast(androidx.lifecycle.Lifecycle.State.STARTED)) {
            return
        }
        if (isAskEnableDialogVisible) {
            return
        }
        hasLatchedAskEnableBrowserTransport = true
        isAskEnableDialogVisible = true
        AlertDialog.Builder(this)
            .setTitle(R.string.browser_transport_prompt_title)
            .setMessage(R.string.browser_transport_prompt_message)
            .setPositiveButton(R.string.browser_transport_prompt_enable) { _, _ ->
                lifecycleScope.launch {
                    runCatching {
                        FireSessionStoreRepository.get(this@MainActivity)
                            .enableBrowserTransportForSession()
                    }
                }
            }
            .setNegativeButton(R.string.browser_transport_prompt_decline) { _, _ ->
                lifecycleScope.launch {
                    runCatching {
                        FireSessionStoreRepository.get(this@MainActivity).declineBrowserTransport()
                    }
                }
            }
            .setOnDismissListener {
                isAskEnableDialogVisible = false
            }
            .show()
    }

    private fun handleSignedOutLaunch(navController: NavController) {
        val entry = intent?.getStringExtra(EXTRA_ONBOARDING_ENTRY) ?: return
        if (entry.isBlank()) return
        intent.removeExtra(EXTRA_ONBOARDING_ENTRY)
        val options = NavOptions.Builder()
            .setPopUpTo(R.id.fire_nav_graph, true)
            .build()
        runCatching {
            navController.navigate(
                R.id.onboardingFragment,
                androidx.core.os.bundleOf("onboardingEntry" to entry),
                options,
            )
        }
    }

    companion object {
        const val EXTRA_ONBOARDING_ENTRY = "fire.onboardingEntry"

        private val bottomTabDestinations = setOf(
            R.id.homeFragment,
            R.id.notificationsFragment,
            R.id.chatFragment,
            R.id.profileFragment,
        )
    }
}
