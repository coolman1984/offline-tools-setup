# PDF Automation Scenarios

- Digital text PDF: native extraction wins; OCR is not run unnecessarily.
- Fully scanned PDF: render + OCR records page coordinates/confidence.
- Mixed scanned/digital PDF: OCR only image regions/pages and deduplicate overlap.
- Rotated/mixed-size pages: coordinate transforms preserve page references.
- Arabic/English/Korean content: language selection and RTL ordering are validated on representative pages.
- Encrypted document without authorized credentials: stop without removing protection.
- Malformed PDF: repair is explicit and source remains untouched.
- Generated executive PDF: reopen, page count, sample rendering, expected text and non-zero output all validate.
