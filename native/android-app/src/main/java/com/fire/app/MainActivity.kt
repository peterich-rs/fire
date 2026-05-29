package com.fire.app

import android.os.Bundle
import android.view.View
import androidx.appcompat.app.AppCompatActivity
import androidx.core.view.ViewCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.updatePadding
import androidx.lifecycle.lifecycleScope
import androidx.navigation.fragment.NavHostFragment
import androidx.navigation.ui.setupWithNavController
import com.fire.app.databinding.ActivityMainBinding
import com.fire.app.session.FireSessionStoreRepository
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

class MainActivity : AppCompatActivity() {

    private lateinit var binding: ActivityMainBinding

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = ActivityMainBinding.inflate(layoutInflater)
        setContentView(binding.root)
        applySystemBarInsets()

        val navHostFragment = supportFragmentManager
            .findFragmentById(R.id.nav_host_fragment) as NavHostFragment
        val navController = navHostFragment.navController

        binding.bottomNav.setupWithNavController(navController)
        navController.addOnDestinationChangedListener { _, destination, _ ->
            binding.bottomNav.visibility = when (destination.id) {
                R.id.onboardingFragment,
                R.id.loginWebViewFragment -> View.GONE
                else -> View.VISIBLE
            }
        }

        refreshNotificationBadge()
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
}
