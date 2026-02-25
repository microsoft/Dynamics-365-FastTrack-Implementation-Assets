import * as React from "react";

import { SAMPLE_IMAGE } from "./images";
import { styles } from "./styles";

interface FieldInfoProps {
  name: string;
  value?: string;
  valueStyles?: React.CSSProperties;
  nameStyles?: React.CSSProperties;
  hideValue?: boolean;
}

const FieldInfo = ({ name, value, valueStyles, nameStyles, hideValue }: FieldInfoProps) => (
    <div style={styles.fieldBox}>
      <span style={nameStyles || (hideValue !== true) ? styles.name : styles.value}>
        {name}{((hideValue !== true)) && ":"}</span>
      {hideValue !== true && (<span style={valueStyles || styles.value}>{value}</span>)}
    </div>
);

const FieldRow = (props) => (
    <div
      style={{
        display: "flex",
        alignItems: "stretch",
        flexDirection: "row",
        maxWidth: `${calculateWindowWidthPercentage()}px`
      }}
    >
      {props.children}
    </div>
  );

const SectionTitle = (props) => (
    <div style={styles.bar}>
      <span style={styles.sectionTitle}>{props.children}</span>
    </div>
);

/**
 * Formats the duration
 * @param duration the duration field retrieved from the query, in minutes.
 */
const formatDuration = (duration: number) => {
    if(!duration) {
return "";
}
    if (duration < 60) {
return `${duration} minute(s)`;
}
    const hours = Math.round(duration * 100 / 60) / 100;
    const days = Math.round(hours * 100 / 24) / 100;
    return days >= 1 ? `${days} day(s)` : `${hours} hour(s)`;
};

/**
 * Calculates the width of the report based on the scale factor and window width.
 */
const calculateWindowWidthPercentage = () => {
    const defaultWidth = 535;
    const scaleFactor = 1.66;
    const widthPercentage = 0.8;
    const offset = -30;
    // For desktop return default
    if(window.innerWidth > 600) {
return defaultWidth;
}
    // Calculate width for mobile
    return (widthPercentage * window.innerWidth * scaleFactor) + offset;
};

/**
 * The main report description. This determines how the report looks.
 * You can pass data from additional entities after adding your custom queries in index.ts
 * This sample already has some data for the booking, products, etc. that is being fetched and passed to this function.
 */
export default ({ booking, products, servicetasks, serviceInfo, signature, services }) => (
    <div>
      <div
        className="mt4"
      >
        {/* Everythng under this div will be printed to PDF */}
        <div id="divToPrint" style={{ marginTop: "50px", marginLeft:"30px", width: `${calculateWindowWidthPercentage()}px` }}>
          <div className="container">
            <div style={{ fontFamily: "sans-serif" }}>
              <h1 style={styles.title}>
                Contoso Service Report
              </h1>

              <div style={styles.address}>
                <div>
                  <div>2000 Willowbrook Mall</div>
                  <div>Huston, TX 77070</div>
                  <div>123-456-789</div>
                </div>
                <div>
                  <img id="header-svg" style={{ float:"right" }} src={SAMPLE_IMAGE} alt="Contoso logo"></img>
                </div>
              </div>

              <SectionTitle>Customer Information</SectionTitle>
              <FieldInfo name="Name" value={serviceInfo?.name} valueStyles={styles.singleColValue}></FieldInfo>
              <FieldInfo name="Address" value={serviceInfo?.address1_composite} valueStyles={styles.singleColValue}></FieldInfo>
              <FieldInfo name="Phone" value={serviceInfo?.telephone1} valueStyles={styles.singleColValue}></FieldInfo>

              <SectionTitle>Service Information</SectionTitle>
              <FieldInfo
                name="Technician"
                value={booking && (booking?.resourcename)}
                valueStyles={styles.singleColValue}
              ></FieldInfo>
              <FieldRow>
                <FieldInfo
                  name="Start Time"
                  value={booking?.formattedStarttime || booking?.starttime}
                ></FieldInfo>
                <FieldInfo name="End Time" value={booking?.formattedEndtime || booking?.endtime}></FieldInfo>
              </FieldRow>
              <FieldRow>
                <FieldInfo
                  name="Duration"
                  value={formatDuration(booking?.duration)}
                ></FieldInfo>
                <FieldInfo name="Incident" value={serviceInfo?.incident}></FieldInfo>
              </FieldRow>

              <SectionTitle>Products</SectionTitle>
              {
                products.map((product) =>
                  <FieldInfo
                    key={product.msdyn_workorderproductid}
                    name={`${product.msdyn_name} (${product.msdyn_quantity})`}
                    hideValue={true}
                  ></FieldInfo>)
              }

              <SectionTitle>Service Tasks</SectionTitle>
              {
                servicetasks.map((servicetask) =>
                  <FieldInfo
                    key={servicetask.msdyn_workorderservicetaskid}
                    name={servicetask.msdyn_name}
                    hideValue={true}
                  ></FieldInfo>)
              }

              <SectionTitle>Services</SectionTitle>
              {
                services.map((service) =>
                  <FieldInfo
                    key={service.msdyn_workorderserviceid}
                    name={service.msdyn_name}
                    hideValue={true}
                  ></FieldInfo>)
              }

              <img style={{ marginTop: "15px", marginLeft: "-10px", width: "30%", ...styles.hideText }} src={signature} alt="Image of signature"/>
              <div style={{ textAlign: "left" }}>Signature</div>
            </div>
          </div>
        </div>
      </div>
    </div>
);
