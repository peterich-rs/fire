package com.fire.app.ui.topicdetail

import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import androidx.recyclerview.widget.RecyclerView
import com.fire.app.R

class LoadingFooterAdapter : RecyclerView.Adapter<LoadingFooterAdapter.FooterViewHolder>() {

    var isLoading: Boolean = false
        set(value) {
            val oldValue = field
            if (oldValue == value) return
            field = value
            if (value) {
                notifyItemInserted(0)
            } else {
                notifyItemRemoved(0)
            }
        }

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): FooterViewHolder {
        val view = LayoutInflater.from(parent.context)
            .inflate(R.layout.item_loading_footer, parent, false)
        return FooterViewHolder(view)
    }

    override fun onBindViewHolder(holder: FooterViewHolder, position: Int) {}

    override fun getItemCount(): Int = if (isLoading) 1 else 0

    class FooterViewHolder(itemView: View) : RecyclerView.ViewHolder(itemView)
}
