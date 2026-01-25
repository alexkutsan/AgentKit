#!/usr/bin/env python3
"""
Simple MCP Server with Streamable HTTP Transport
Used for testing Crystal Agent MCP integration.
"""

import os
import random
import sys
from mcp.server.fastmcp import FastMCP
from pydantic import Field

# configurable port by environment variable
port = int(os.environ.get("MCP_SERVER_PORT", 8000))

# Create a basic stateless MCP server
mcp = FastMCP(name="Simple MCP Server with Streamable HTTP Transport", port=port)

# Add debug logging flag based on environment variable
DEBUG = os.environ.get("MCP_DEBUG", "0").lower() in ("1", "true", "yes")

@mcp.tool()
def hello_world(name: str = "World") -> str:
    """Say hello to someone"""
    result = f"Hello, {name}!"
    if DEBUG:
        print(f"[DEBUG] hello_world called with name={name} -> {result}")
    return result

@mcp.tool()
def add_numbers(a: float, b: float) -> float:
    """Add two numbers together"""
    result = a + b
    if DEBUG:
        print(f"[DEBUG] add_numbers called with a={a}, b={b} -> {result}")
    return result

@mcp.tool()
def random_number(min_val: int = 0, max_val: int = 100) -> int:
    """Generate a random integer between min_val and max_val (inclusive)"""
    if min_val > max_val:
        min_val, max_val = max_val, min_val
    result = random.randint(min_val, max_val)
    if DEBUG:
        print(f"[DEBUG] random_number called with min_val={min_val}, max_val={max_val} -> {result}")
    return result

@mcp.tool()
def return_json_example() -> dict:
    """Return a JSON example"""
    result = {"message": "This is a JSON response", "status": "success"}
    if DEBUG:
        print(f"[DEBUG] return_json_example called -> {result}")
    return result

@mcp.tool()
def calculate_bmi(weight: float, height: float) -> str:
    """Calculate BMI from weight and height"""
    bmi = weight / (height ** 2)
    result = f"Your BMI is {bmi:.2f}"
    if DEBUG:
        print(f"[DEBUG] calculate_bmi called with weight={weight}, height={height} -> {result}")
    return result

@mcp.resource("server://info")
async def get_server_info() -> str:
    """Get information about this server"""
    return "This is a simple MCP server with streamable HTTP transport. It supports tools for greeting, adding numbers, generating random numbers, and calculating BMI. It also provides a BMI calculator prompt."

@mcp.prompt(title="BMI Calculator", description="Calculate BMI from weight and height")
def prompt_bmi_calculator(
    weight: float = Field(description="Weight in kilograms (kg)"),
    height: float = Field(description="Height in meters (m)")
) -> str:
    """Calculate BMI from weight and height"""
    return f"Please calculate my BMI using the following information: Weight: {weight} kg, Height: {height} m."

def main():
    """Main entry point for the MCP server"""
    transport = os.environ.get("MCP_TRANSPORT", "streamable-http").strip().lower()
    if transport not in ("streamable-http", "stdio"):
        raise SystemExit(f"Unsupported MCP_TRANSPORT: {transport}")

    out = sys.stderr if transport == "stdio" else sys.stdout
    print("Starting Simple MCP Server...", file=out)
    print("Available tools: hello_world, add_numbers, random_number, calculate_bmi", file=out)
    print("Available prompts: BMI Calculator", file=out)
    print("Available resources: server://info", file=out)

    # Run with selected transport
    mcp.run(transport=transport)

if __name__ == "__main__":
    main()
