#include "SteamApiLoader.h"

#ifdef F4MP_STEAM

#include <Windows.h>
#include "steam/steam_api.h"
#include <cstdio>
#include <cwchar>

// ───────────────────────────────────────────────────────────────────────────
// Dynamic binding to a privately-named steam_api64 copy. We deliberately do NOT
// link steam_api64.lib (see f4mp.vcxproj F4MPSteam group / STEAM_API_NODLL), so
// the handful of flat Steamworks symbols the SDK headers reference are DEFINED
// below and forwarded to steam_api64_f4mp.dll, loaded at runtime from the
// plugin's own directory. The game's steam_api64.dll is never loaded by name here.
// ───────────────────────────────────────────────────────────────────────────

namespace
{
	HMODULE g_dll    = nullptr;
	bool    g_inited = false;

	// Forwarded export pointers (S_CALLTYPE == __cdecl).
	void*       (S_CALLTYPE *p_ContextInit)(void*)                                = nullptr;
	void*       (S_CALLTYPE *p_CreateInterface)(const char*)                      = nullptr;
	void*       (S_CALLTYPE *p_FindOrCreateUser)(HSteamUser, const char*)         = nullptr;
	void*       (S_CALLTYPE *p_FindOrCreateGS)(HSteamUser, const char*)           = nullptr;
	HSteamUser  (S_CALLTYPE *p_GetHSteamUser)()                                   = nullptr;
	HSteamPipe  (S_CALLTYPE *p_GetHSteamPipe)()                                   = nullptr;
	void        (S_CALLTYPE *p_RegCallback)(CCallbackBase*, int)                  = nullptr;
	void        (S_CALLTYPE *p_UnregCallback)(CCallbackBase*)                     = nullptr;
	void        (S_CALLTYPE *p_RegCallResult)(CCallbackBase*, SteamAPICall_t)     = nullptr;
	void        (S_CALLTYPE *p_UnregCallResult)(CCallbackBase*, SteamAPICall_t)   = nullptr;
	void        (S_CALLTYPE *p_RunCallbacks)()                                    = nullptr;
	ESteamAPIInitResult (S_CALLTYPE *p_InitFlat)(SteamErrMsg*)                    = nullptr;
	void        (S_CALLTYPE *p_Shutdown)()                                        = nullptr;

	template <typename T> void Bind(T& fp, const char* name)
	{
		fp = g_dll ? reinterpret_cast<T>(GetProcAddress(g_dll, name)) : nullptr;
	}

	// Load steam_api64_f4mp.dll from the folder this plugin lives in (never the
	// game-root steam_api64.dll) and bind every forwarded export. Idempotent.
	bool LoadDll()
	{
		if (g_dll) return true;

		wchar_t path[MAX_PATH] = {};
		HMODULE self = nullptr;
		if (GetModuleHandleExW(
				GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS | GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
				reinterpret_cast<LPCWSTR>(&LoadDll), &self) && self)
		{
			DWORD n = GetModuleFileNameW(self, path, MAX_PATH);
			if (n > 0 && n < MAX_PATH)
			{
				wchar_t* slash = wcsrchr(path, L'\\');
				if (slash)
				{
					const size_t cap = MAX_PATH - (size_t)(slash + 1 - path);
					wcscpy_s(slash + 1, cap, L"steam_api64_f4mp.dll");
					g_dll = LoadLibraryW(path);
				}
			}
		}
		if (!g_dll) g_dll = LoadLibraryW(L"steam_api64_f4mp.dll"); // fallback: default search order
		if (!g_dll)
		{
			printf("[steam-loader] could not load steam_api64_f4mp.dll (next to f4mp.dll)\n");
			return false;
		}

		Bind(p_ContextInit,      "SteamInternal_ContextInit");
		Bind(p_CreateInterface,  "SteamInternal_CreateInterface");
		Bind(p_FindOrCreateUser, "SteamInternal_FindOrCreateUserInterface");
		Bind(p_FindOrCreateGS,   "SteamInternal_FindOrCreateGameServerInterface");
		Bind(p_GetHSteamUser,    "SteamAPI_GetHSteamUser");
		Bind(p_GetHSteamPipe,    "SteamAPI_GetHSteamPipe");
		Bind(p_RegCallback,      "SteamAPI_RegisterCallback");
		Bind(p_UnregCallback,    "SteamAPI_UnregisterCallback");
		Bind(p_RegCallResult,    "SteamAPI_RegisterCallResult");
		Bind(p_UnregCallResult,  "SteamAPI_UnregisterCallResult");
		Bind(p_RunCallbacks,     "SteamAPI_RunCallbacks");
		Bind(p_InitFlat,         "SteamAPI_InitFlat");
		Bind(p_Shutdown,         "SteamAPI_Shutdown");
		return true;
	}
}

namespace f4mp
{
	namespace steamapi
	{
		bool EnsureInit()
		{
			if (g_inited) return true;
			if (!LoadDll()) return false;
			if (!p_InitFlat)
			{
				printf("[steam-loader] SteamAPI_InitFlat missing from steam_api64_f4mp.dll\n");
				return false;
			}

			SteamErrMsg err = {};
			ESteamAPIInitResult r = p_InitFlat(&err);
			if (r != k_ESteamAPIInitResult_OK)
			{
				printf("[steam-loader] SteamAPI_InitFlat failed (res=%d): %s\n", (int)r, err);
				return false;
			}

			g_inited = true;
			printf("[steam-loader] initialised via steam_api64_f4mp.dll "
				"(game's steam_api64.dll untouched)\n");
			return true;
		}

		void Shutdown()
		{
			if (g_inited && p_Shutdown) p_Shutdown();
			g_inited = false;
		}
	}
}

// ───────────────────────────────────────────────────────────────────────────
// Flat-API definitions the SDK headers expect under STEAM_API_NODLL. Each just
// forwards to the privately-named shim. LoadDll() self-initialises so these work
// even when hit early (e.g. CCallback registration during SteamSpike construction).
// ───────────────────────────────────────────────────────────────────────────
extern "C"
{
	S_API void* S_CALLTYPE SteamInternal_ContextInit(void* p)
	{ LoadDll(); return p_ContextInit ? p_ContextInit(p) : nullptr; }

	S_API void* S_CALLTYPE SteamInternal_CreateInterface(const char* v)
	{ LoadDll(); return p_CreateInterface ? p_CreateInterface(v) : nullptr; }

	S_API void* S_CALLTYPE SteamInternal_FindOrCreateUserInterface(HSteamUser u, const char* v)
	{ LoadDll(); return p_FindOrCreateUser ? p_FindOrCreateUser(u, v) : nullptr; }

	S_API void* S_CALLTYPE SteamInternal_FindOrCreateGameServerInterface(HSteamUser u, const char* v)
	{ LoadDll(); return p_FindOrCreateGS ? p_FindOrCreateGS(u, v) : nullptr; }

	S_API HSteamUser S_CALLTYPE SteamAPI_GetHSteamUser()
	{ LoadDll(); return p_GetHSteamUser ? p_GetHSteamUser() : 0; }

	S_API HSteamPipe S_CALLTYPE SteamAPI_GetHSteamPipe()
	{ LoadDll(); return p_GetHSteamPipe ? p_GetHSteamPipe() : 0; }

	S_API void S_CALLTYPE SteamAPI_RegisterCallback(CCallbackBase* cb, int i)
	{ LoadDll(); if (p_RegCallback) p_RegCallback(cb, i); }

	S_API void S_CALLTYPE SteamAPI_UnregisterCallback(CCallbackBase* cb)
	{ LoadDll(); if (p_UnregCallback) p_UnregCallback(cb); }

	S_API void S_CALLTYPE SteamAPI_RegisterCallResult(CCallbackBase* cb, SteamAPICall_t h)
	{ LoadDll(); if (p_RegCallResult) p_RegCallResult(cb, h); }

	S_API void S_CALLTYPE SteamAPI_UnregisterCallResult(CCallbackBase* cb, SteamAPICall_t h)
	{ LoadDll(); if (p_UnregCallResult) p_UnregCallResult(cb, h); }

	S_API void S_CALLTYPE SteamAPI_RunCallbacks()
	{ LoadDll(); if (p_RunCallbacks) p_RunCallbacks(); }
}

#endif // F4MP_STEAM
