FROM justb4/jmeter:5.1.1

# https://jmeter-plugins.org/wiki/TestPlanCheckTool/
ENV PLAN_CHECK_PLUGIN_VERSION=2.4
RUN wget https://jmeter-plugins.org/files/packages/jpgc-plancheck-${PLAN_CHECK_PLUGIN_VERSION}.zip
RUN unzip -o jpgc-plancheck-${PLAN_CHECK_PLUGIN_VERSION}.zip -d ${JMETER_HOME}

EXPOSE 1099

ENTRYPOINT ["/entrypoint.sh"]