import html2canvas from "html2canvas"; // REQUIRED
import jsPDF from "jspdf/dist/jspdf.es.min";

// Example of adding font to report.
// Refer to JSPDF documentation online for more information and detailed steps.
// var callAddFont = function () {
// this.addFileToVFS('test.ttf', font);
// this.addFont('test.ttf', 'test', 'normal');
// };
// jsPDF.API.events.push(['addFonts', callAddFont])

/**
 * Generates a pdf from the report's html and calls the onSave callback with the pdf data.
 * Will convert everything under div with id 'divToPrint'. This can be changed if you would like to print from a different element.
 * @param onSave callback that will be called with the pdf binary data as it's argument
 */
export const printDocument = (onSave) => async () => {
  const input = document.getElementById("divToPrint");
 
   let pdf = new jsPDF("p", "pt", "a4"); 
  pdf.setProperties({
    title: "PDF Title",
    subject: "PDF Sample",
    author: "Microsoft",
    keywords: "generated, javascript",
    creator: "Microsoft",
  }); 
    pdf.setLanguage("en");

    /**
     * Embedding Custom Fonts

     //#region Base64 Custom Fonts
     const customFont = 'BASE64 CONTENT';
     //#endregion
    
     pdf.addFileToVFS("customFont.ttf", customFont);
     pdf.addFont("customFont.ttf", "customFontName", "normal");
     pdf.setFont("customFontName", "normal");

     //Note: the 'customFontName' should match the font from the generated HTML report. 
     //The default font is 'sans-serif'. See SampleReport\style.ts
    */

  pdf.html(input, {
    callback: (htmlPDF) => {
      // Can trigger a download directly to device
      // htmlPDF.save("test.pdf");

      // Save pdf to timeline/notes
      let data = htmlPDF.output("datauristring");
      onSave(data);
    },
    autoPaging: 'text'
  });
};
