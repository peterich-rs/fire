package com.fire.app.ui.home

import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.EditText
import android.widget.LinearLayout
import android.widget.TextView
import androidx.core.widget.doAfterTextChanged
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import com.fire.app.R
import com.fire.app.core.ext.dp
import com.fire.app.displayName
import com.google.android.material.bottomsheet.BottomSheetDialogFragment
import uniffi.fire_uniffi_session.TopicCategoryState

class HomeCategoryDrawerFragment : BottomSheetDialogFragment() {

    var categories: List<TopicCategoryState> = emptyList()
    var selectedCategoryId: ULong? = null
    var onSelect: (ULong?) -> Unit = {}

    override fun onCreateView(
        inflater: LayoutInflater,
        container: ViewGroup?,
        savedInstanceState: Bundle?,
    ): View {
        val context = requireContext()
        val root = LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(context.dp(16), context.dp(12), context.dp(16), context.dp(24))
        }
        val title = TextView(context).apply {
            text = getString(R.string.home_category_drawer_title)
            setTextAppearance(androidx.appcompat.R.style.TextAppearance_AppCompat_Title)
        }
        val search = EditText(context).apply {
            hint = getString(R.string.home_category_search_hint)
            setSingleLine()
            setBackgroundResource(R.drawable.bg_scope_capsule)
            setPadding(context.dp(14), context.dp(10), context.dp(14), context.dp(10))
        }
        val list = RecyclerView(context).apply {
            layoutManager = LinearLayoutManager(context)
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                context.dp(420),
            )
        }
        val parents = HomeScopePresentation.parents(categories)
        val adapter = CategoryDrawerAdapter(parents, selectedCategoryId) { id ->
            onSelect(id)
            dismiss()
        }
        list.adapter = adapter
        search.doAfterTextChanged { text ->
            val query = text?.toString()?.trim().orEmpty().lowercase()
            val filtered = if (query.isEmpty()) {
                parents
            } else {
                parents.filter {
                    it.displayName().lowercase().contains(query) || it.slug.lowercase().contains(query)
                }
            }
            adapter.submit(filtered)
        }
        root.addView(title)
        root.addView(search, LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.WRAP_CONTENT,
        ).apply { topMargin = context.dp(12) })
        root.addView(list, LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            context.dp(420),
        ).apply { topMargin = context.dp(8) })
        return root
    }

    private class CategoryDrawerAdapter(
        private var parents: List<TopicCategoryState>,
        private val selectedCategoryId: ULong?,
        private val onSelect: (ULong?) -> Unit,
    ) : RecyclerView.Adapter<CategoryDrawerAdapter.Holder>() {
        fun submit(next: List<TopicCategoryState>) {
            parents = next
            notifyDataSetChanged()
        }

        override fun getItemCount(): Int = parents.size + 1

        override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): Holder {
            val view = TextView(parent.context).apply {
                layoutParams = RecyclerView.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT,
                    parent.context.dp(52),
                )
                setPadding(parent.context.dp(8), 0, parent.context.dp(8), 0)
                gravity = android.view.Gravity.CENTER_VERTICAL
                setTextAppearance(androidx.appcompat.R.style.TextAppearance_AppCompat_Subhead)
            }
            return Holder(view)
        }

        override fun onBindViewHolder(holder: Holder, position: Int) {
            val text = holder.itemView as TextView
            if (position == 0) {
                text.text = "全部"
                text.setTextColor(text.context.getColor(R.color.fire_text_primary))
                holder.itemView.setOnClickListener { onSelect(null) }
            } else {
                val category = parents[position - 1]
                text.text = category.displayName()
                val selectedParent = selectedCategoryId
                text.setTextColor(
                    if (selectedParent == category.id) {
                        text.context.getColor(R.color.fire_accent)
                    } else {
                        text.context.getColor(R.color.fire_text_primary)
                    },
                )
                holder.itemView.setOnClickListener { onSelect(category.id) }
            }
        }

        class Holder(view: View) : RecyclerView.ViewHolder(view)
    }
}

class HomeSubcategorySheetFragment : BottomSheetDialogFragment() {

    var shortcuts: List<HomeChildShortcut> = emptyList()
    var onSelect: (ULong) -> Unit = {}

    override fun onCreateView(
        inflater: LayoutInflater,
        container: ViewGroup?,
        savedInstanceState: Bundle?,
    ): View {
        val context = requireContext()
        val root = LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(context.dp(16), context.dp(12), context.dp(16), context.dp(24))
        }
        root.addView(TextView(context).apply {
            text = getString(R.string.home_subcategory_title)
            setTextAppearance(androidx.appcompat.R.style.TextAppearance_AppCompat_Title)
        })
        shortcuts.forEach { shortcut ->
            root.addView(TextView(context).apply {
                text = shortcut.title
                setPadding(0, context.dp(14), 0, context.dp(14))
                setTextColor(
                    context.getColor(
                        if (shortcut.isSelected) R.color.fire_accent else R.color.fire_text_primary,
                    ),
                )
                setOnClickListener {
                    onSelect(shortcut.categoryId)
                    dismiss()
                }
            })
        }
        return root
    }
}
