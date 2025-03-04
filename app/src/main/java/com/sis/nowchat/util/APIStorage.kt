package com.sis.nowchat.util

import android.content.Context
import android.util.Base64
import android.util.Log
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import com.google.gson.Gson
import com.sis.nowchat.model.APIModel
import kotlinx.coroutines.flow.first


val Context.apiDataStore: DataStore<Preferences> by preferencesDataStore(name = "api_data")

class APIStorage(private val context: Context) {

    // 定义存储的键
    private fun apiKey(id: String) = stringPreferencesKey("api_$id")
    // 当前模型键
    private val currentApiIdKey = stringPreferencesKey("current_api_id")

    // 保存用户当前选择的 API ID 和模型
    suspend fun saveCurrentSelection(apiId: String) {
        context.apiDataStore.edit { preferences ->
            preferences[currentApiIdKey] = apiId
        }
    }

    // 获取用户当前选择的 API ID 和模型
    suspend fun getCurrentSelection(): String? {
        val preferences = context.apiDataStore.data.first()
        val apiId = preferences[currentApiIdKey]
        return apiId
    }

    // 保存 API 数据
    suspend fun saveAPI(apiModel: APIModel) {
        val id = apiModel.id
        val apiDataWithoutKey = apiModel.copy(apiKey = "") // 移除 apiKey
        val jsonString = Gson().toJson(apiDataWithoutKey)
        // 保存普通数据到 DataStore
        context.apiDataStore.edit { preferences ->
            preferences[apiKey(id)] = jsonString
        }
        // 加密并保存 apiKey 到 Keystore
        val (iv, encryptedKey) = KeystoreHelper.encrypt(id, apiModel.apiKey)
        // 将 IV 和加密后的数据转换为 Base64 字符串
        val ivBase64 = android.util.Base64.encodeToString(iv, android.util.Base64.DEFAULT)
        val encryptedKeyBase64 = android.util.Base64.encodeToString(encryptedKey, android.util.Base64.DEFAULT)
        // 保存 IV 和加密后的数据到 DataStore
        context.apiDataStore.edit { preferences ->
            preferences[stringPreferencesKey("iv_$id")] = ivBase64
            preferences[stringPreferencesKey("key_$id")] = encryptedKeyBase64
            Log.d("APIStorage", "Saved IV: $ivBase64, Encrypted key: $encryptedKeyBase64")
        }
    }


    // 获取 API 数据
    suspend fun getAPI(id: String): APIModel? {
        val preferences = context.apiDataStore.data.first()
        // 从 DataStore 获取普通数据
        val apiDataString = preferences[apiKey(id)] ?: return null
        val apiModelWithoutKey = Gson().fromJson(apiDataString, APIModel::class.java)
        // 从 DataStore 获取 IV 和加密后的数据
        val ivBase64 = preferences[stringPreferencesKey("iv_$id")] ?: return null
        val encryptedKeyBase64 = preferences[stringPreferencesKey("key_$id")] ?: return null
        // 将 Base64 字符串解码为 ByteArray
        val iv = android.util.Base64.decode(ivBase64, android.util.Base64.DEFAULT)
        val encryptedKey = android.util.Base64.decode(encryptedKeyBase64, android.util.Base64.DEFAULT)
        // 解密 apiKey
        val decryptedKey = try {
            KeystoreHelper.decrypt(id, iv, encryptedKey)
        } catch (e: Exception) {
            Log.e("APIStorage", "Failed to decrypt key for id: $id", e)
            null
        }
        // 返回完整的 APIModel
        return apiModelWithoutKey.copy(apiKey = decryptedKey ?: "")
    }

    // 获取所有 API 数据
    suspend fun getAllAPIs(): List<APIModel> {
        val preferences = context.apiDataStore.data.first()
        return preferences.asMap().keys
            .filter { it.name.startsWith("api_") } // 过滤出以 "api_" 开头的键
            .mapNotNull { key ->
                val id = key.name.removePrefix("api_")
                getAPI(id)
            }
    }

    // 删除 API 数据
    suspend fun deleteAPI(id: String) {
        context.apiDataStore.edit { preferences ->
            preferences.remove(apiKey(id))
            preferences.remove(stringPreferencesKey("key_$id"))
        }
    }

}