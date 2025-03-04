package com.sis.nowchat.util

import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Log
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

object KeystoreHelper {

    private const val KEYSTORE_ALIAS_PREFIX = "api_key_"

    // 生成秘钥
    fun generateKey(id: String): SecretKey {
        val keyGenerator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore")
        keyGenerator.init(
            KeyGenParameterSpec.Builder(
                "$KEYSTORE_ALIAS_PREFIX$id",
                KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT
            )
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .build()
        )
        val secretKey = keyGenerator.generateKey()
        return secretKey
    }

    // 获取秘钥
    fun getKey(id: String): SecretKey? {
        val keyStore = KeyStore.getInstance("AndroidKeyStore")
        keyStore.load(null)
        val key = keyStore.getKey("$KEYSTORE_ALIAS_PREFIX$id", null) as? SecretKey
        return key
    }

    // 加密数据
    fun encrypt(id: String, data: String): Pair<ByteArray, ByteArray> {
        val secretKey = getKey(id) ?: generateKey(id)
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, secretKey)
        val iv = cipher.iv // 获取生成的 IV
        val encryptedData = cipher.doFinal(data.toByteArray(Charsets.UTF_8))
        return Pair(iv, encryptedData) // 返回 IV 和加密后的数据
    }


    // 解密数据
    fun decrypt(id: String, iv: ByteArray, encryptedData: ByteArray): String {
        val secretKey = getKey(id) ?: throw IllegalStateException("Key not found for id: $id")
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        val spec = GCMParameterSpec(128, iv) // 使用存储的 IV
        cipher.init(Cipher.DECRYPT_MODE, secretKey, spec)
        return String(cipher.doFinal(encryptedData), Charsets.UTF_8)
    }


}