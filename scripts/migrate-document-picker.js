const fs = require('fs');
const path = require('path');

const file = path.join(process.cwd(), 'src', 'MessengerHome.tsx');
if (!fs.existsSync(file)) process.exit(0);

let s = fs.readFileSync(file, 'utf8');

s = s.replace(
  "import DocumentPicker from'react-native-document-picker';",
  "import {pick,types,isErrorWithCode,errorCodes} from'@react-native-documents/picker';"
);

s = s.replace(
  "const r=await DocumentPicker.pickSingle({type:[DocumentPicker.types.allFiles]});if(!selected||!r.uri)return;",
  "const [r]=await pick({type:[types.allFiles]});if(!selected||!r?.uri)return;"
);

s = s.replace(
  "if(DocumentPicker.isCancel(e))return;",
  "if(isErrorWithCode(e)&&e.code===errorCodes.OPERATION_CANCELED)return;"
);

fs.writeFileSync(file, s);
