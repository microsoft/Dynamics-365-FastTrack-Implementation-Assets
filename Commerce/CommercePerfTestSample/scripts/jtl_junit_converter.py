import sys, csv
from datetime import datetime
from xml.etree import ElementTree
from xml.dom import minidom
from xml.etree.ElementTree import Element, SubElement, Comment

# jtl table columns
TIMESTAMP = 0
ELAPSED = 1
LABEL = 2
RESPONSE_MESSAGE = 4
SUCCESS = 7

def prettify(elem):
	"""Returns a pretty-printed XML string for the Element.
	"""
	rough_string = ElementTree.tostring(elem, 'utf-8')
	reparsed = minidom.parseString(rough_string)
	return reparsed.toprettyxml(indent="  ")

def retrieve_jmeter_results(jmeter_file):
	"""Returns a list of JMeter JTL rows without header.
	The JMeter JTL file must be in CSV format.
	"""
	csv_reader = csv.reader(jmeter_file)
	next(csv_reader)
	return list(csv_reader)

def create_request_attrib(jmeter_result):
	"""Returns a JSON with attributes for a JUnit testsuite: https://llg.cubic.org/docs/junit/
	The JMeter JTL file must be in CSV format.
	"""
	request_time = float(jmeter_result[ELAPSED])/1000.0

	return {
		'name': jmeter_result[LABEL],
		'time': str(request_time),
		'error_message': jmeter_result[RESPONSE_MESSAGE]
	}

def create_test_case_attrib(request_attrib):
	"""Returns a JSON with attributes for a JUnit testcase: https://llg.cubic.org/docs/junit/
	The JMeter JTL file must be in CSV format.
	"""
	return {
		'classname': 'httpSample',
		'name': request_attrib['name'],
		'time': request_attrib['time']
}

def create_test_suite_attrib(junit_results):
	"""Returns a JSON with attributes for JUnit testsuite: https://llg.cubic.org/docs/junit/
	The JMeter JTL file must be in CSV format.
	"""
	return {
		'id': '1',
		'name': 'load test',
		'package': 'load test',
		'hostname': 'Azure DevOps',
		'time': str(junit_results['time']),
		'tests': str(junit_results['tests']),
		'failures': str(len(junit_results['requests']['failures'])),
		'errors': '0'
	}

def create_error_test_case_attrib(error_message):
	"""Returns a JSON with attributes for JUnit testcase for failed requests: https://llg.cubic.org/docs/junit/
	The JMeter JTL file must be in CSV format.
	"""
	return {
		'message': error_message,
		'type': 'exception'
	}
  
def requests(jmeter_results):
	"""Returns a JSON with successful and failed HTTP requests.
	The JMeter JTL file must be in CSV format.
	"""
	failed_requests = []
	successful_requests = []

	for result in jmeter_results:
		request_attrib = create_request_attrib(result)

		if result[SUCCESS] == 'true':
			successful_requests.append(request_attrib)
		else:
			failed_requests.append(request_attrib)

	return {
		'success': successful_requests,
		'failures': failed_requests
	}

def total_time_seconds(jmeter_results):
	"""Returns the total test duration in seconds.
	The JMeter JTL file must be in CSV format.
	"""
	max_timestamp = max(jmeter_results, key=lambda result: int(result[TIMESTAMP]))
	min_timestamp = min(jmeter_results, key=lambda result: int(result[TIMESTAMP]))
	total_timestamp = int(max_timestamp[TIMESTAMP]) - int(min_timestamp[TIMESTAMP])

	return float(total_timestamp)/1000.0

def create_junit_results(jtl_results_filename):
	with open(jtl_results_filename) as jmeter_file:
		jmeter_results = retrieve_jmeter_results(jmeter_file)
		time = total_time_seconds(jmeter_results)

		return {
			'tests': len(jmeter_results),
			'time': time,
			'requests': requests(jmeter_results),
		}

def create_properties(test_suite):
	"""Creates a JUnit properties element for testsuite: https://llg.cubic.org/docs/junit/
	The JMeter JTL file must be in CSV format.
	"""
	return SubElement(test_suite, 'properties')

def create_test_suite(test_suites, junit_results):
	"""Creates a JUnit testsuite: https://llg.cubic.org/docs/junit/
	The JMeter JTL file must be in CSV format.
	"""
	test_suite_attrib = create_test_suite_attrib(junit_results)
	test_suite = SubElement(test_suites, 'testsuite', test_suite_attrib)

	create_properties(test_suite)

	failed_requests = len(junit_results['requests']['failures'])
	successful_requests = len(junit_results['requests']['success'])

	for success_index in range(successful_requests):
		successful_request = junit_results['requests']['success'][success_index]
		create_successful_test_case(test_suite, successful_request)

	for error_index in range(failed_requests):
		failed_request = junit_results['requests']['failures'][error_index]
		create_failed_test_case(test_suite, failed_request)

def create_failed_test_case(test_suite, failed_request):
	"""Creates a JUnit test case for failed HTTP requests: https://llg.cubic.org/docs/junit/
	The JMeter JTL file must be in CSV format.
	"""
	test_case_attrib = create_test_case_attrib(failed_request)
	error_test_case_attrib = create_error_test_case_attrib(failed_request['error_message'])

	test_case = SubElement(test_suite, 'testcase', test_case_attrib)
	test_case_error = SubElement(test_case, 'error', error_test_case_attrib)

def create_successful_test_case(test_suite, successful_request):
	"""Creates a JUnit test case for successful HTTP requests: https://llg.cubic.org/docs/junit/
	The JMeter JTL file must be in CSV format.
	"""
	test_case_attrib = create_test_case_attrib(successful_request)
	test_case = SubElement(test_suite, 'testcase', test_case_attrib)

def create_test_suites(jtl_results_filename):
	"""Creates a JUnit testsuites element: https://llg.cubic.org/docs/junit/
	The JMeter JTL file must be in CSV format.
	"""
	test_suites = Element('testsuites')
	junit_results = create_junit_results(jtl_results_filename)
	create_test_suite(test_suites, junit_results)

	return prettify(test_suites)

def main():
  print('Converting...')
  
  with open(sys.argv[2], "w") as output_file:
    test_suites = create_test_suites(sys.argv[1])
    output_file.write(test_suites)

  print('Done!')
    
if __name__ == '__main__':
	main()
