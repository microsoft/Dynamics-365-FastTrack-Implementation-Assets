# Inventory Stock Availability Agent - Responsible AI and Usage FAQ

## 1. What does this agent do?

It helps users check on-hand, reserved, and available inventory in Dynamics 365 Finance and Operations by item, warehouse, and legal entity.

## 2. Can it change inventory or reserve stock?

No. Its intended inventory workflow is read-only. It does not reserve, transfer, allocate, purchase, or modify inventory. Administrators must enforce the read-only tool allowlist and remove unrelated capabilities.

## 3. What information must users provide?

An item number and legal entity are required. Provide a warehouse for a specific-warehouse lookup. Natural-language requests can explicitly ask for all warehouses. The agent must not assume a default legal entity.

## 4. Does the agent respect existing Dynamics 365 permissions?

The ERP MCP connection must use the signed-in user's identity. Dynamics 365 permissions and applicable legal-entity restrictions govern access. Sharing the agent does not grant additional ERP permissions.

## 5. Does available inventory guarantee fulfillment?

No. Results reflect the data returned when queried. Inventory can change immediately afterward, and the agent does not reserve stock or make a delivery commitment.

## 6. Can AI-generated results be incorrect?

Yes. AI can misunderstand requests or interpret results incorrectly. Verify important quantities, units, warehouse details, and legal entities in Dynamics 365 before making operational decisions.

## 7. What happens when no inventory record is found?

The agent should explicitly report that no matching record was found. This is not the same as confirming zero stock. For JSON responses, check `RecordFound: false`; zero placeholders must not be interpreted as verified balances.

## 8. How does it handle multiple inventory dimension rows?

It returns the rows separately rather than assuming they can be combined. Users must review relevant inventory dimensions and units before interpreting availability.

## 9. What happens if access is denied or a tool fails?

The agent should report the failure without inventing inventory quantities. Administrators should investigate authentication, permissions, connection configuration, or service availability.

## 10. What data does the solution process?

It processes user requests and inventory information returned by Dynamics 365. Prompts, responses, and diagnostics may contain business-sensitive information. Administrators must review applicable Power Platform data policies, transcript settings, retention, and access controls.

## 11. What must administrators validate before deployment?

Verify end-user authentication, the three-tool read-only allowlist, legal-entity restrictions, connection bindings, and responses in the intended channel. Remove unrelated Work IQ capabilities and test in an isolated environment before production use.

## 12. Is the published package production-certified?

No. Archive inspection confirms that the supplied package includes the inventory skill and ERP MCP tool components, but does not establish production readiness. A clean import and end-to-end acceptance testing are still required.

## 13. What disclaimer accompanies successful responses?

"This is an AI-generated output and should be reviewed for accuracy and completeness prior to distribution."

For installation, configuration, and validation details, see the [agent guide](./README.md).
