/* eslint-disable @typescript-eslint/no-explicit-any */
import { ReportPreview } from "../../ReportPreview/index";

const mockPrintDocumentFn = jest.fn();

// Mock pdfPrinter
jest.mock("../../ReportPreview/helpers/pdfPrinter", () => ({ printDocument: () => mockPrintDocumentFn }));

// Mock ReportViewer component
jest.mock("../../ReportPreview/ReportViewer", () => {
    return jest.fn(() => null);
});

// Mock GetReportData
const mockGetBookingData = jest.fn().mockResolvedValue({});
const mockGetProducts = jest.fn().mockResolvedValue({});
const mockGetServiceTasks = jest.fn().mockResolvedValue({});
const mockGetServices = jest.fn().mockResolvedValue({});
const mockGetServiceInfo = jest.fn().mockResolvedValue({});
jest.mock("../../ReportPreview/DataProviders/GetReportData", () => {
    return {
        GetReportData: jest.fn().mockImplementation(() => {
            return {
                getBookingData: mockGetBookingData,
                getProducts: mockGetProducts,
                getServiceTasks: mockGetServiceTasks,
                getServices: mockGetServices,
                getServiceInfo: mockGetServiceInfo
            };
        })
    };
});

describe("ReportPreview", () => {
    let control = new ReportPreview();
    const resetViewFake = jest.fn();
    const renderFake = jest.fn();
    const fetchFake = jest.fn().mockReturnValue([Promise.resolve()]);
    let getDataFetchPromisesSpy: jest.SpyInstance;

    beforeEach(() => {
        jest.spyOn(control, "renderReportViewer").mockImplementation(renderFake);
        jest.spyOn(control, "resetReportView").mockImplementation(resetViewFake);
        getDataFetchPromisesSpy = jest.spyOn(control, "getDataFetchPromises").mockImplementation(fetchFake);
    });

    afterEach(() => {
        jest.clearAllMocks();
        control = new ReportPreview();
    });

    describe("init", () => {
        it("should initialize data properly and trigger data fetch", () => {
            const fake = {} as any;

            control.init(({ parameters: { ReportView: { raw: undefined }, BookingId: { formatted: "test" }, WorkOrder: { raw: [{ id: "test" }] } } } as any),
                jest.fn(), fake, fake);

            expect(resetViewFake).toHaveBeenCalledTimes(0);
            expect(renderFake).toHaveBeenCalled();
            expect(fetchFake).toHaveBeenCalled();
        });

        it("should not fetch data if missing work order and booking ID", () => {
            const fake = {} as any;

            control.init(({ parameters: { ReportView: { raw: true } } } as any), jest.fn(), fake, fake);

            expect(resetViewFake).toHaveBeenCalled();
            expect(renderFake).toHaveBeenCalled();
            expect(fetchFake).toHaveBeenCalledTimes(0);
        });

    });

    describe("updateView", () => {
        it("should rerender to display new signature", () => {
            const fake = {} as any;
            const initContext = { parameters: { ReportView: { raw: undefined }, Signature: { raw: "old" } } } as any;
            const updateContext = { parameters: { ReportView: { raw: undefined }, Signature: { raw: "new" } } } as any;

            control.init(initContext, jest.fn(), fake, fake);
            control.updateView(updateContext);

            expect(renderFake).toHaveBeenCalledTimes(2);
        });

        it("should trigger pdf generation on new event", () => {
            const fake = {} as any;
            const initContext = { parameters: { ReportView: { raw: undefined }, BookingId: { formatted: "test" } } } as any;
            const updateContext = { parameters: { ReportView: { raw: "save" }, BookingId: { formatted: "test" } } } as any;

            control.init(initContext, jest.fn(), fake, fake);
            control.updateView(updateContext);

            expect(mockPrintDocumentFn).toHaveBeenCalled();
        });
    });

    describe("getDataFetchPromises", () => {
        it("should trigger all the data fetch methods in the data getter class", () => {
            const fake = {} as any;

            control.init(({ parameters: { ReportView: { raw: undefined }, BookingId: { formatted: "test" }, WorkOrder: { raw: [{ id: "test" }] } } } as any),
                jest.fn(), fake, fake);

            getDataFetchPromisesSpy.mockRestore();
            const result: Array<any> = control.getDataFetchPromises();

            expect(mockGetBookingData).toHaveBeenCalled();
            expect(mockGetProducts).toHaveBeenCalled();
            expect(mockGetServiceTasks).toHaveBeenCalled();
            expect(mockGetServices).toHaveBeenCalled();
            expect(mockGetServiceInfo).toHaveBeenCalled();

            expect(result.length).toBe(5);
        });
    });
});
