from pathlib import Path
import unittest

from excel_loader import load_workbook, validate_workbook


class SampleTemplateTests(unittest.TestCase):
    def test_sample_template_loads_without_local_validation_issues(self) -> None:
        sample_path = Path(__file__).resolve().parents[1] / "sample_template.xlsx"

        workbook = load_workbook(sample_path.read_bytes())

        self.assertGreater(len(workbook.projects), 0)
        self.assertGreater(len(workbook.tasks), 0)
        self.assertEqual(validate_workbook(workbook), [])


if __name__ == "__main__":
    unittest.main()