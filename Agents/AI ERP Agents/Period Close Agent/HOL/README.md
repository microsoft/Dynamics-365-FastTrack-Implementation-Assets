# Period Close Agent – hands-on lab

**Solution:** PeriodCloseAgentV2 1.1.0.0 · **Company:** USMF · **Period:** October 2026

## Start here

Choose one way to follow the lab:

- **Option A – interactive wizard.** Download
  [`PeriodCloseAgent_HOL_Wizard.html`](PeriodCloseAgent_HOL_Wizard.html) and open it in Edge or
  Chrome. It walks you through every step with checklists, copy buttons for agent prompts,
  enlargeable screenshots and built-in file downloads. Progress is saved in your browser, and it
  works offline.
- **Option B – Word guide.**
  1. Open [`HOL_PeriodCloseAgent_External.docx`](HOL_PeriodCloseAgent_External.docx). If the page
     numbers in the Contents show 1, right-click the Contents and select **Update Field** >
     **Update entire table** (or press F9 in Word).
  2. Follow Part 1 (install and configure), Part 2 (run close scenarios) and Part 3 (add business
     skills).
  3. Appendix B covers troubleshooting and how to reset the lab for the next learner.

## What is in this package

| Item | Purpose |
| --- | --- |
| [`HOL_PeriodCloseAgent_External.docx`](HOL_PeriodCloseAgent_External.docx) | The lab guide. |
| [`PeriodCloseAgent_HOL_Wizard.html`](PeriodCloseAgent_HOL_Wizard.html) | Interactive step-by-step version of the guide (works offline). |
| [`../Solutions/PeriodCloseAgentV2_1_1_0_0_unmanaged.zip`](../Solutions/PeriodCloseAgentV2_1_1_0_0_unmanaged.zip) | The solution to import in Step 8. The wizard also has a download button for it. |
| [`Sample journals/`](Sample%20journals) | Payroll, IFRS 9 and IFRS 16 CSV files to upload to SharePoint in Step 7. |
| [`Business skill/PeriodClose_MonthlyDepreciation.md`](Business%20skill/PeriodClose_MonthlyDepreciation.md) | Sample skill added in Part 3 (Steps 16–19). |
| [`Business skill/PeriodClose_SkillTemplate.md`](Business%20skill/PeriodClose_SkillTemplate.md) | Blank template for writing your own skill (Step 20). |

## Before you run the lab in your own tenant

- Create your own SharePoint site and folders (Step 7) and enter its URL in the four skills
  (Step 12). The solution ships with the placeholder `{{SHAREPOINT_SITE_URL}}` in those four
  skills; replace it with your site URL.
- Give each responsible worker on agent-enabled tasks an email address, or review emails are not
  sent.
- Scenario 2 (Accounts payable currency revaluation) posts directly. Use a test environment.
- Your administrator enables the Period Close Agent capability, the ERP MCP server and the virtual
  tables.

> [!IMPORTANT]
> Production use is gated and controlled by Microsoft. Microsoft enables the Period Close Agent
> capability for production environments on request; register through the
> [Period Close Agent sign-up form](https://aka.ms/PeriodCloseAgentSignUp). Lab, evaluation and
> sandbox environments do not need this. This gating will change as the capability matures.
