# Changelog

All notable changes to the Microsoft Release Planner MCP Server will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2025-12-18

### Added
- Initial release of Microsoft Release Planner MCP Server
- Three main MCP tools:
  - `search_release_plans`: Search and filter release plans by product, wave, status, keywords
  - `list_products`: List all available products with optional feature counts
  - `get_release_wave_summary`: Get release wave statistics and breakdowns
- Zod schema validation for runtime type safety
- 1-hour in-memory caching mechanism to reduce API calls
- TypeScript support with full type definitions
- Comprehensive filtering capabilities:
  - Filter by product name
  - Filter by feature keywords
  - Filter by release wave
  - Filter by status (early_access, public_preview, ga, all)
  - Filter by investment area
- Documentation:
  - README.md with quick start, Copilot Studio integration, and Responsible AI section
  - MCP_SERVER_GUIDE.md with complete step-by-step creation and deployment guide
  - TOOLS.md with tool reference and examples
  - CHANGELOG.md for version tracking
- Express.js HTTP server with `/mcp` endpoint
- Health check endpoint at `/health`

### Features
- Fetches data from public Microsoft Release Planner API
- No authentication required
- **Copilot Studio MCP integration** via dev tunnels
- Efficient in-memory caching with 1-hour TTL
- Error handling and validation
- Case-insensitive search
- Partial string matching for filters
- Text-based responses for maximum compatibility

### Technical Details
- Built with TypeScript (ES2022)
- Uses `@modelcontextprotocol/sdk` ^1.20.2
- Uses Zod ^3.22.4 for validation
- Uses Express.js ^4.18.2 for HTTP server
- ES Module format
- **StreamableHTTPServerTransport** for MCP over HTTP
- Manual JSON schema definitions (no `zod-to-json-schema`)
- Follows Microsoft's official MCP server pattern (cybersource-status-mcp)
- Port 3000 by default
- JSON-RPC 2.0 protocol

### Implementation Pattern
- Simple if-statement tool handlers
- Text-only responses
- Manual inputSchema objects
- Express POST endpoint at `/mcp`
- Proper error handling with isError flag
- Health check endpoint for monitoring

---

## Roadmap

Future enhancements being considered:

### [1.1.0] - Planned
- [ ] Add pagination support for large result sets
- [ ] Add sorting options (by date, product, feature name)
- [ ] Add date range filtering
- [ ] Enhanced error messages with validation details
- [ ] Configurable cache TTL via environment variables
- [ ] Response time metrics and logging

### [1.2.0] - Planned
- [ ] Add feature comparison tool
- [ ] Add release timeline visualization data
- [ ] Add geographic availability filtering
- [ ] Export results to different formats
- [ ] Search history and favorites

### [2.0.0] - Future
- [ ] Support for multiple languages
- [ ] Historical data tracking
- [ ] Webhook support for real-time updates
- [ ] Custom report generation
- [ ] Integration with other Microsoft APIs
- [ ] Advanced analytics and insights

---

## Version History

### Version Numbering

- **Major version** (X.0.0): Breaking changes, major new features
- **Minor version** (1.X.0): New features, backward compatible
- **Patch version** (1.0.X): Bug fixes, minor improvements

### Release Notes Format

Each release includes:
- **Added**: New features
- **Changed**: Changes to existing functionality
- **Deprecated**: Features to be removed in future versions
- **Removed**: Features removed in this version
- **Fixed**: Bug fixes
- **Security**: Security improvements

---

## Contributing

When contributing to this project:
1. Update CHANGELOG.md with your changes
2. Follow the format above
3. Add your changes under "Unreleased" section
4. Maintainers will move changes to appropriate version on release

---

## Support

For questions about specific versions:
- Check the version with `npm list --depth=0`
- Review the CHANGELOG for that version
- Refer to documentation files for implementation details

---

[1.0.0]: https://github.com/microsoft/Dynamics-365-FastTrack-Implementation-Assets/tree/master/Agents/Implementation%20Agents/Release%20Planner
