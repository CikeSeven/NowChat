package com.sis.nowchat.manager

import android.content.Context
import androidx.datastore.preferences.core.booleanPreferencesKey
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map

// 扩展属性：初始化 DataStore
val Context.dataStore by preferencesDataStore(name = "app_settings")

class SettingsManager(private val context: Context) {

    // 定义键值对的 Key
    companion object {
        private val THEME_MODE_KEY = booleanPreferencesKey("is_dark_theme")
        private val USER_NAME_KEY = stringPreferencesKey("user_name")
    }

    // 读取是否启用暗黑主题
    val isDarkTheme: Flow<Boolean> = context.dataStore.data.map { preferences ->
        preferences[THEME_MODE_KEY] ?: false // 默认为亮色主题
    }

    // 保存是否启用暗黑主题
    suspend fun saveThemeMode(isDarkTheme: Boolean) {
        context.dataStore.edit { preferences ->
            preferences[THEME_MODE_KEY] = isDarkTheme
        }
    }

    // 读取用户名
    val userName: Flow<String?> = context.dataStore.data.map { preferences ->
        preferences[USER_NAME_KEY]
    }

    // 保存用户名
    suspend fun saveUserName(userName: String) {
        context.dataStore.edit { preferences ->
            preferences[USER_NAME_KEY] = userName
        }
    }

    // 清除所有设置
    suspend fun clearSettings() {
        context.dataStore.edit { preferences ->
            preferences.clear()
        }
    }
}