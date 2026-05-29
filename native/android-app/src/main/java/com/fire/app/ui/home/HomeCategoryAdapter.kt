package com.fire.app.ui.home

import android.view.View
import android.view.ViewGroup
import androidx.recyclerview.widget.RecyclerView
import com.fire.app.displayName
import com.google.android.material.chip.Chip
import uniffi.fire_uniffi_session.TopicCategoryState

class HomeCategoryAdapter(
    private var categories: List<TopicCategoryState>,
    private var selectedCategoryId: ULong?,
    private val onCategorySelected: (ULong?) -> Unit,
) : RecyclerView.Adapter<HomeCategoryAdapter.CategoryViewHolder>() {

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): CategoryViewHolder {
        val chip = Chip(parent.context).apply {
            isClickable = true
            isCheckable = true
        }
        chip.layoutParams = ViewGroup.LayoutParams(
            ViewGroup.LayoutParams.WRAP_CONTENT,
            ViewGroup.LayoutParams.WRAP_CONTENT,
        )
        return CategoryViewHolder(chip)
    }

    override fun onBindViewHolder(holder: CategoryViewHolder, position: Int) {
        val chip = holder.itemView as Chip
        val category = categories.getOrNull(position - 1)
        val categoryId = category?.id
        chip.text = category?.displayName() ?: "全部"
        chip.isChecked = categoryId == selectedCategoryId
        chip.setOnClickListener {
            onCategorySelected(categoryId)
            if (categoryId == selectedCategoryId) {
                chip.isChecked = true
            }
        }
    }

    override fun getItemCount(): Int = categories.size + 1

    fun updateCategories(nextCategories: List<TopicCategoryState>) {
        val parentCategories = nextCategories.filter { it.parentCategoryId == null }
        if (categories == parentCategories) return
        categories = parentCategories
        notifyDataSetChanged()
    }

    fun updateSelectedCategory(categoryId: ULong?) {
        if (selectedCategoryId == categoryId) return
        val previousCategoryId = selectedCategoryId
        selectedCategoryId = categoryId
        notifyCategoryChanged(previousCategoryId)
        notifyCategoryChanged(categoryId)
    }

    private fun notifyCategoryChanged(categoryId: ULong?) {
        val index = if (categoryId == null) {
            0
        } else {
            val categoryIndex = categories.indexOfFirst { it.id == categoryId }
            if (categoryIndex < 0) return
            categoryIndex + 1
        }
        notifyItemChanged(index)
    }

    class CategoryViewHolder(itemView: View) : RecyclerView.ViewHolder(itemView)
}
