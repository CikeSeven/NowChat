package com.sis.nowchat.viewmodel

import android.content.Context
import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider

class ConversationViewModelFactory(private val appContext: Context) : ViewModelProvider.Factory {
    override fun <T : ViewModel> create(modelClass: Class<T>): T {
        if (modelClass.isAssignableFrom(ConversationViewModel::class.java)) {
            @Suppress("UNCHECKED_CAST")
            return ConversationViewModel(appContext) as T
        }
        throw IllegalArgumentException("Unknown ViewModel class")
    }
}