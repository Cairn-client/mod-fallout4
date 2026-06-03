#define LIBRG_IMPLEMENTATION
//#define LIBRG_DISABLE_FEATURE_ENTITY_VISIBILITY

#include "Server.h"

#include <iostream>
#include <fstream>
#include <csignal>
#include <chrono>

f4mp::Server* f4mp::Server::instance = nullptr;

// A7: graceful shutdown. The handler must do almost nothing (it runs in a
// signal/console context), so it only flips this flag; the main loop sees it,
// breaks, and tears the server down cleanly on the normal thread.
namespace
{
	volatile std::sig_atomic_t g_running = 1;

	void HandleShutdownSignal(int)
	{
		g_running = 0;
	}
}

int main()
{
	const std::string configFilePath = "server_config.txt";

	std::string address;
	i32 port = 7779;

	// C2: spawn point is config-driven (optional x y z after address+port).
	// Defaults to the original hardcoded location when absent/malformed.
	zpl_vec3 spawnPoint{ 886.134460f, -426.953460f, -1550.012817f };

	std::ifstream config(configFilePath);
	if (config)
	{
		config >> address;
		config >> port;

		// Optional spawn override: only accept it if all three coords parse,
		// otherwise keep the default (a partial line shouldn't half-apply).
		zpl_vec3 fileSpawn;
		if (config >> fileSpawn.x >> fileSpawn.y >> fileSpawn.z)
		{
			spawnPoint = fileSpawn;
		}

		config.close();
	}
	else
	{
		std::cout << "address? ";
		std::cin >> address;

		std::ofstream file(configFilePath);
		// Write the spawn defaults too, so the file documents the full format.
		file << address << std::endl << port << std::endl
			<< spawnPoint.x << " " << spawnPoint.y << " " << spawnPoint.z;

		std::cout << std::endl;
	}

	// Validate config: a malformed/missing port leaves an out-of-range value
	// (a failed stream extraction yields 0 since C++11), which silently fails
	// to bind. Fall back to the default and warn instead of dying quietly.
	if (port <= 0 || port > 65535)
	{
		std::cout << "invalid port in " << configFilePath << "; using default 7779" << std::endl;
		port = 7779;
	}
	// Empty address is fine: librg treats "" / "localhost" as bind-to-all.

	std::cout << "binding " << (address.empty() ? "(all interfaces)" : address) << ":" << port << std::endl;
	std::cout << "player spawn point: " << spawnPoint.x << " " << spawnPoint.y << " " << spawnPoint.z << std::endl;

    f4mp::Server* server = new f4mp::Server(address, port, spawnPoint);

	server->Start();

	// A7: trap Ctrl-C / kill so we can stop the network cleanly instead of
	// being hard-killed (which leaves clients hanging until their own timeout).
	std::signal(SIGINT, HandleShutdownSignal);
	std::signal(SIGTERM, HandleShutdownSignal);

	// A7: periodic "N players connected" status line so the operator can see
	// liveness without grepping the per-event log spam.
	auto lastStatus = std::chrono::steady_clock::now();
	u32 lastReported = (u32)-1;
	const auto statusInterval = std::chrono::seconds(15);

	while (g_running)
	{
		server->Tick();

		auto now = std::chrono::steady_clock::now();
		if (now - lastStatus >= statusInterval)
		{
			lastStatus = now;
			u32 players = server->PlayerCount();
			if (players != lastReported)
			{
				lastReported = players;
				std::cout << "[status] " << players << " player(s) connected" << std::endl;
			}
		}
	}

	std::cout << std::endl << "shutting down; disconnecting clients..." << std::endl;

	// ~Server() calls librg_network_stop + librg_free, which disconnects peers
	// cleanly so clients see a real disconnect rather than a half-open link.
	delete server;

	std::cout << "server stopped." << std::endl;

	return 0;
}