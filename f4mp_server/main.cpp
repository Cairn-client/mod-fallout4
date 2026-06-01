#define LIBRG_IMPLEMENTATION
//#define LIBRG_DISABLE_FEATURE_ENTITY_VISIBILITY

#include "Server.h"

#include <iostream>
#include <fstream>

f4mp::Server* f4mp::Server::instance = nullptr;

int main()
{
	const std::string configFilePath = "server_config.txt";

	std::string address;
	i32 port = 7779;

	std::ifstream config(configFilePath);
	if (config)
	{
		config >> address;
		config >> port;
		config.close();
	}
	else
	{
		std::cout << "address? ";
		std::cin >> address;

		std::ofstream file(configFilePath);
		file << address << std::endl << port;

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

    f4mp::Server* server = new f4mp::Server(address, port);

	server->Start();

	while (true)
	{
		server->Tick();
	}

	return 0;
}