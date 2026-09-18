#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>

public Plugin myinfo =
{
	name = "Desync Fix",
	author = "Laurens",
	description = "Sync rocket simulation with each owner's user commands.",
	version = "0.1.0",
};

#define MAX_EDICTS (1 << 11)
#define MAX_PROJECTILES 64

enum struct SyncedProjectile
{
	int ref;
	int createdCmd;
	bool nonCmd;
	int spawnOffset;
}

enum struct PendingProjectile
{
	int ref;
	int queuedTick;
}

Handle g_hGameConf;
Handle g_hPhysicsSimulateEntity = INVALID_HANDLE;

ConVar g_cvEnabled;
ConVar g_cvNonCmd;
ConVar g_cvNonCmdOffset;

int g_iOffsetSimulationTick = -1;
int g_iOffsetSimulationTime = -1;
int g_iOffsetBaseVelocity = -1;

int g_iCmdSerial[MAXPLAYERS + 1];
int g_iCmdTickBaseBefore[MAXPLAYERS + 1];
bool g_bInsideRunCmd[MAXPLAYERS + 1];

SyncedProjectile g_Projectiles[MAXPLAYERS + 1][MAX_PROJECTILES];
int g_iNumProjectiles[MAXPLAYERS + 1];

PendingProjectile g_PendingProjectiles[MAX_EDICTS];
int g_iNumPending;

int g_iOwnerByEntity[MAX_EDICTS];
int g_iRefByEntity[MAX_EDICTS];

public void OnPluginStart()
{
	g_hGameConf = LoadGameConfigFile("desyncfix");
	if (g_hGameConf == null)
		SetFailState("[desyncfix] Unable to load gamedata/desyncfix.txt.");

	PreparePhysicsSimulateEntity();

	g_cvEnabled = CreateConVar(
		"sm_desyncfix_enabled",
		"1",
		"Enable the rocket desync fix.",
		_,
		true,
		0.0,
		true,
		1.0);
	g_cvNonCmd = CreateConVar(
		"sm_desyncfix_noncmd",
		"1",
		"Also sync rockets spawned outside their owner's user commands.",
		_,
		true,
		0.0,
		true,
		1.0);
	g_cvNonCmdOffset = CreateConVar(
		"sm_desyncfix_noncmd_offset",
		"0",
		"New non-command rockets: positive adds steps on first owner tick; negative holds that many owner ticks. Range -64 to 64.",
		_,
		true,
		-64.0,
		true,
		64.0);
	g_cvEnabled.AddChangeHook(ConVarChanged_Enabled);
	g_cvNonCmd.AddChangeHook(ConVarChanged_NonCmd);

	ResetAllState();
}

public void OnMapStart()
{
	ResetAllState();
}

public void OnClientDisconnect(int client)
{
	ClearClientProjectiles(client);
	g_iCmdSerial[client] = 0;
	g_iCmdTickBaseBefore[client] = 0;
	g_bInsideRunCmd[client] = false;
}

public void OnGameFrame()
{
	if (!g_cvEnabled.BoolValue)
		return;

	ProcessPendingProjectiles();
	StampTrackedProjectiles(GetGameTickCount());
}

public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float vel[3], float angles[3], int &weapon, int &subtype, int &cmdnum, int &tickcount, int &seed, int mouse[2])
{
	if (g_cvEnabled.BoolValue && IsHumanPlayer(client)) {
		ProcessPendingProjectiles();
		g_iCmdTickBaseBefore[client] = GetEntProp(client, Prop_Send, "m_nTickBase");
		g_iCmdSerial[client]++;
		g_bInsideRunCmd[client] = true;
	}

	return Plugin_Continue;
}

public void OnPlayerRunCmdPost(int client, int buttons, int impulse, const float vel[3], const float angles[3], int weapon, int subtype, int cmdnum, int tickcount, int seed, const int mouse[2])
{
	bool hadCommand = g_bInsideRunCmd[client];
	g_bInsideRunCmd[client] = false;

	if (!hadCommand || !g_cvEnabled.BoolValue || !IsHumanPlayer(client))
		return;

	int tickBaseDelta = GetEntProp(client, Prop_Send, "m_nTickBase") - g_iCmdTickBaseBefore[client];
	// The post hook also runs when the engine rejects a command without simulating it.
	if (tickBaseDelta != 1)
		return;

	SyncClientProjectiles(client);
}

public void OnEntityCreated(int entity, const char[] classname)
{
	if (!g_cvEnabled.BoolValue)
		return;

	if (!IsSyncProjectileClass(classname))
		return;

	SDKHook(entity, SDKHook_SpawnPost, OnProjectileSpawnPost);
}

public void OnEntityDestroyed(int entity)
{
	if (!(0 <= entity < MAX_EDICTS))
		return;

	int owner = g_iOwnerByEntity[entity];
	int ref = g_iRefByEntity[entity];
	if (1 <= owner <= MaxClients && ref != INVALID_ENT_REFERENCE) {
		int index = FindTrackedProjectileByRef(owner, ref);
		if (index != -1)
			RemoveClientProjectileAt(owner, index);
	}

	g_iOwnerByEntity[entity] = 0;
	g_iRefByEntity[entity] = INVALID_ENT_REFERENCE;
}

public void OnProjectileSpawnPost(int entity)
{
	if (!g_cvEnabled.BoolValue || !IsProjectileEntity(entity))
		return;

	int owner = GetProjectileOwner(entity);
	if (IsHumanPlayer(owner)) {
		TrackProjectile(entity, owner, !g_bInsideRunCmd[owner]);
	} else if (owner <= 0) {
		QueuePendingProjectile(entity);
	}
}

void ConVarChanged_Enabled(ConVar convar, const char[] oldValue, const char[] newValue)
{
	ResetTracking();
}

void ConVarChanged_NonCmd(ConVar convar, const char[] oldValue, const char[] newValue)
{
	if (convar.BoolValue)
		return;

	for (int client = 1; client <= MaxClients; client++) {
		for (int i = g_iNumProjectiles[client] - 1; i >= 0; i--) {
			if (g_Projectiles[client][i].nonCmd)
				RemoveClientProjectileAt(client, i);
		}
	}
}

void EnsureRequiredOffsets(int entity)
{
	if (OffsetsReady())
		return;

	g_iOffsetSimulationTick = FindDataMapInfo(entity, "m_nSimulationTick");
	g_iOffsetSimulationTime = FindDataMapInfo(entity, "m_flSimulationTime");
	g_iOffsetBaseVelocity = FindDataMapInfo(entity, "m_vecBaseVelocity");

	if (!OffsetsReady()) {
		SetFailState(
			"[desyncfix] Offset lookup failed from entity %d: simtick=%d simtime=%d basevel=%d",
			entity,
			g_iOffsetSimulationTick,
			g_iOffsetSimulationTime,
			g_iOffsetBaseVelocity);
	}
}

bool OffsetsReady()
{
	return g_iOffsetSimulationTick != -1
		&& g_iOffsetSimulationTime != -1
		&& g_iOffsetBaseVelocity != -1;
}

void PreparePhysicsSimulateEntity()
{
	StartPrepSDKCall(SDKCall_Static);
	if (!PrepSDKCall_SetFromConf(g_hGameConf, SDKConf_Signature, "Physics_SimulateEntity"))
		SetFailState("[desyncfix] Unable to find Physics_SimulateEntity signature.");

	PrepSDKCall_AddParameter(SDKType_CBaseEntity, SDKPass_Pointer);

	g_hPhysicsSimulateEntity = EndPrepSDKCall();
	if (g_hPhysicsSimulateEntity == INVALID_HANDLE)
		SetFailState("[desyncfix] Unable to prepare Physics_SimulateEntity SDKCall.");
}

void QueuePendingProjectile(int entity)
{
	int ref = EntIndexToEntRef(entity);
	for (int i = 0; i < g_iNumPending; i++) {
		if (g_PendingProjectiles[i].ref == ref)
			return;
	}

	if (g_iNumPending >= MAX_EDICTS)
		return;

	g_PendingProjectiles[g_iNumPending].ref = ref;
	g_PendingProjectiles[g_iNumPending].queuedTick = GetGameTickCount();
	g_iNumPending++;
}

void ProcessPendingProjectiles()
{
	int tick = GetGameTickCount();
	int write;
	for (int i = 0; i < g_iNumPending; i++) {
		int entity = EntRefToEntIndex(g_PendingProjectiles[i].ref);
		if (!IsProjectileEntity(entity))
			continue;

		int owner = GetProjectileOwner(entity);
		if (IsHumanPlayer(owner)) {
			TrackProjectile(entity, owner, true);
			continue;
		}

		if (owner <= 0 && tick == g_PendingProjectiles[i].queuedTick) {
			g_PendingProjectiles[write] = g_PendingProjectiles[i];
			write++;
		}
	}
	g_iNumPending = write;
}

void TrackProjectile(int entity, int owner, bool nonCmd)
{
	if (!g_cvEnabled.BoolValue || !IsProjectileEntity(entity))
		return;

	int ref = EntIndexToEntRef(entity);
	if (ref == INVALID_ENT_REFERENCE)
		return;

	if (FindTrackedProjectileByRef(owner, ref) != -1)
		return;

	if (nonCmd && !g_cvNonCmd.BoolValue)
		return;

	if (g_iNumProjectiles[owner] >= MAX_PROJECTILES)
		return;

	EnsureRequiredOffsets(entity);

	int index = g_iNumProjectiles[owner]++;
	g_Projectiles[owner][index].ref = ref;
	g_Projectiles[owner][index].createdCmd = g_iCmdSerial[owner];
	g_Projectiles[owner][index].nonCmd = nonCmd;
	g_Projectiles[owner][index].spawnOffset = nonCmd ? g_cvNonCmdOffset.IntValue : 0;
	g_iOwnerByEntity[entity] = owner;
	g_iRefByEntity[entity] = ref;

	SetSimulationTick(entity, GetGameTickCount());
}

void StampTrackedProjectiles(int tick)
{
	for (int client = 1; client <= MaxClients; client++) {
		for (int i = g_iNumProjectiles[client] - 1; i >= 0; i--) {
			int entity = EntRefToEntIndex(g_Projectiles[client][i].ref);
			if (!IsProjectileEntity(entity) || GetProjectileOwner(entity) != client) {
				RemoveClientProjectileAt(client, i);
				continue;
			}

			if (!IsPredictableProjectile(entity))
				continue;

			SetSimulationTick(entity, tick);
		}
	}
}

void SyncClientProjectiles(int client)
{
	int tick = GetGameTickCount();
	float frameSimTime = float(tick) * GetTickInterval();

	for (int i = g_iNumProjectiles[client] - 1; i >= 0; i--) {
		int ref = g_Projectiles[client][i].ref;
		int entity = EntRefToEntIndex(ref);
		if (!IsProjectileEntity(entity) || GetProjectileOwner(entity) != client) {
			RemoveClientProjectileAt(client, i);
			continue;
		}

		if (g_Projectiles[client][i].createdCmd == g_iCmdSerial[client])
			continue;

		if (!IsPredictableProjectile(entity))
			continue;

		int offset = g_Projectiles[client][i].spawnOffset;
		if (offset < 0) {
			g_Projectiles[client][i].spawnOffset++;
			SetSimulationTick(entity, tick);
			continue;
		}

		int steps = 1 + offset;
		g_Projectiles[client][i].spawnOffset = 0;

		for (int step = 0; step < steps; step++) {
			if (!SimulateProjectileStep(client, ref, tick, frameSimTime))
				break;
		}
	}
}

bool SimulateProjectileStep(int client, int ref, int tick, float frameSimTime)
{
	int entity = EntRefToEntIndex(ref);
	if (!g_cvEnabled.BoolValue || !IsProjectileEntity(entity))
		return false;

	if (g_iOwnerByEntity[entity] != client || g_iRefByEntity[entity] != ref || GetProjectileOwner(entity) != client)
		return false;

	if (!IsPredictableProjectile(entity))
		return false;

	SetSimulationTick(entity, tick - 1);
	SDKCall(g_hPhysicsSimulateEntity, entity);

	if (EntRefToEntIndex(ref) == entity && IsProjectileEntity(entity)) {
		SetSimulationTick(entity, tick);
		SetFrameSimulationTime(entity, frameSimTime);
	}

	return true;
}

void SetFrameSimulationTime(int entity, float simTime)
{
	SetEntDataFloat(entity, g_iOffsetSimulationTime, simTime, true);
}

void ClearClientProjectiles(int client)
{
	for (int i = 0; i < g_iNumProjectiles[client]; i++) {
		int entity = EntRefToEntIndex(g_Projectiles[client][i].ref);
		if (0 <= entity < MAX_EDICTS && g_iRefByEntity[entity] == g_Projectiles[client][i].ref) {
			g_iOwnerByEntity[entity] = 0;
			g_iRefByEntity[entity] = INVALID_ENT_REFERENCE;
		}
	}

	g_iNumProjectiles[client] = 0;
}

void RemoveClientProjectileAt(int client, int index)
{
	if (!(1 <= client <= MaxClients))
		return;

	if (!(0 <= index < g_iNumProjectiles[client]))
		return;

	int ref = g_Projectiles[client][index].ref;
	int entity = EntRefToEntIndex(ref);
	if (0 <= entity < MAX_EDICTS && g_iRefByEntity[entity] == ref) {
		g_iOwnerByEntity[entity] = 0;
		g_iRefByEntity[entity] = INVALID_ENT_REFERENCE;
	}

	for (int i = index; i < g_iNumProjectiles[client] - 1; i++)
		g_Projectiles[client][i] = g_Projectiles[client][i + 1];

	g_iNumProjectiles[client]--;
}

void ResetAllState()
{
	ResetTracking();

	for (int client = 1; client <= MaxClients; client++) {
		g_iCmdSerial[client] = 0;
		g_iCmdTickBaseBefore[client] = 0;
		g_bInsideRunCmd[client] = false;
	}
}

void ResetTracking()
{
	g_iNumPending = 0;
	for (int client = 1; client <= MaxClients; client++)
		g_iNumProjectiles[client] = 0;

	for (int entity = 0; entity < MAX_EDICTS; entity++) {
		g_iOwnerByEntity[entity] = 0;
		g_iRefByEntity[entity] = INVALID_ENT_REFERENCE;
	}
}

int FindTrackedProjectileByRef(int owner, int ref)
{
	if (!(1 <= owner <= MaxClients))
		return -1;

	for (int i = 0; i < g_iNumProjectiles[owner]; i++) {
		if (g_Projectiles[owner][i].ref == ref)
			return i;
	}

	return -1;
}

bool IsSyncProjectileClass(const char[] classname)
{
	return StrEqual(classname, "tf_projectile_rocket")
		|| StrEqual(classname, "tf_projectile_energy_ball");
}

bool IsProjectileEntity(int entity)
{
	return entity > MaxClients
		&& entity < MAX_EDICTS
		&& IsValidEdict(entity);
}

bool IsHumanPlayer(int client)
{
	return 1 <= client <= MaxClients
		&& IsClientInGame(client)
		&& !IsFakeClient(client);
}

bool IsPredictableProjectile(int entity)
{
	MoveType movetype = view_as<MoveType>(GetEntProp(entity, Prop_Data, "m_MoveType"));
	if (movetype != MOVETYPE_FLY)
		return false;

	return !HasBaseVelocity(entity);
}

bool HasBaseVelocity(int entity)
{
	float baseVelocity[3];
	GetEntDataVector(entity, g_iOffsetBaseVelocity, baseVelocity);

	return FloatAbs(baseVelocity[0]) >= 0.001
		|| FloatAbs(baseVelocity[1]) >= 0.001
		|| FloatAbs(baseVelocity[2]) >= 0.001;
}

int GetProjectileOwner(int entity)
{
	return GetEntPropEnt(entity, Prop_Data, "m_hOwnerEntity");
}

void SetSimulationTick(int entity, int tick)
{
	SetEntData(entity, g_iOffsetSimulationTick, tick);
}
