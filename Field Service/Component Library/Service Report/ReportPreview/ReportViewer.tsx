import * as React from "react";

import { Spinner } from "@fluentui/react/lib/Spinner";
import { SpinnerSize } from "@fluentui/react/lib/Spinner";

import { SpinnerHelper } from "./helpers/SpinnerHelper";
import { ReportViewerProps } from "./models/ReportViewerModel";
import SampleReport from "./SampleReport/SampleReport";

export default class ReportViewer extends React.Component<ReportViewerProps> {

    componentDidMount() {
      // Additional logic to be executed after the component is mounted
    }

    private customAction = async (_data: string) => {
      // If you want any custom interactions that want to use the report data
    };

    render() {
      return (
        <div className="wrap" style={{marginLeft: "-15px"}}>
          <SampleReport
            // customAction={(printDocument(this.customAction))}
            booking={this.props.booking}
            products={this.props.products}
            servicetasks={this.props.servicetasks}
            serviceInfo={this.props.serviceInfo}
            signature={this.props.signature}
            {...this.props}
            />
            {this.props.isSpinnerVisible ?
              (<div className="spinnerOverlay">
                  <Spinner size={SpinnerSize.large} styles={SpinnerHelper.spinnerStyles} />
              </div>) : null}
        </div>
      );
    }
}
