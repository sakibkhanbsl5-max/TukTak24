const SHEET_NAME = 'Gift Cards';
const HEADERS = ['Code','Discount','Issued At','Expires At','Status','Customer Name','Customer Mobile','Redeemed At','Order Number','Created By'];

function doGet() {
  return HtmlService.createHtmlOutputFromFile('Index')
    .setTitle('TukTak24 Gift Card')
    .addMetaTag('viewport', 'width=device-width, initial-scale=1');
}

// Run once from the Apps Script editor. It creates the sheet and a random first admin password.
function setupGiftCardSystem() {
  const props = PropertiesService.getScriptProperties();
  let id = props.getProperty('SHEET_ID');
  let ss;
  if (id) {
    ss = SpreadsheetApp.openById(id);
  } else {
    ss = SpreadsheetApp.create('TukTak24 Gift Card Database');
    props.setProperty('SHEET_ID', ss.getId());
  }
  let sh = ss.getSheetByName(SHEET_NAME) || ss.insertSheet(SHEET_NAME);
  if (sh.getLastRow() === 0) {
    sh.appendRow(HEADERS);
    sh.setFrozenRows(1);
    sh.getRange(1,1,1,HEADERS.length).setFontWeight('bold').setBackground('#17243a').setFontColor('#ffffff');
    sh.autoResizeColumns(1, HEADERS.length);
  }
  let password = props.getProperty('ADMIN_PASSWORD');
  if (!password) {
    password = Utilities.getUuid().replace(/-/g,'').slice(0,16);
    props.setProperty('ADMIN_PASSWORD', password);
  }
  Logger.log('Gift Card spreadsheet: ' + ss.getUrl());
  Logger.log('Initial admin password (save it, then change it in Script Properties): ' + password);
  return 'Setup complete. Open the execution log to copy the spreadsheet URL and initial admin password.';
}

function getSheet_() {
  const id = PropertiesService.getScriptProperties().getProperty('SHEET_ID');
  if (!id) throw new Error('প্রথমে Apps Script থেকে setupGiftCardSystem চালাও।');
  return SpreadsheetApp.openById(id).getSheetByName(SHEET_NAME);
}

function loginAdmin(password) {
  const expected = PropertiesService.getScriptProperties().getProperty('ADMIN_PASSWORD');
  if (!expected || !password || password !== expected) throw new Error('পাসওয়ার্ড সঠিক নয়।');
  const token = Utilities.getUuid() + Utilities.getUuid();
  CacheService.getScriptCache().put('admin_' + token, '1', 21600);
  return {token: token, expiresIn: 21600};
}

function requireAdmin_(token) {
  if (!token || CacheService.getScriptCache().get('admin_' + token) !== '1') {
    throw new Error('সেশন শেষ হয়েছে। আবার লগইন করো।');
  }
}

function createGiftCards(token, options) {
  requireAdmin_(token);
  const count = Math.max(1, Math.min(100, Number(options.count) || 1));
  const discount = Number(options.discount);
  const expiry = String(options.expiry || '');
  if (!Number.isFinite(discount) || discount < 1 || discount > 100) throw new Error('ডিসকাউন্ট ১ থেকে ১০০ শতাংশের মধ্যে হতে হবে।');
  if (!/^\d{4}-\d{2}-\d{2}$/.test(expiry)) throw new Error('সঠিক মেয়াদ শেষের তারিখ দাও।');
  const sh = getSheet_();
  const rows = [];
  const created = [];
  for (let i=0; i<count; i++) {
    const code = 'TT24-' + Utilities.getUuid().replace(/-/g,'').slice(0,8).toUpperCase();
    rows.push([code, discount, new Date(), new Date(expiry + 'T23:59:59'), 'Unused', '', '', '', '', Session.getActiveUser().getEmail() || 'Admin']);
    created.push(code);
  }
  sh.getRange(sh.getLastRow()+1, 1, rows.length, HEADERS.length).setValues(rows);
  return {codes: created};
}

function verifyGiftCard(code) {
  code = String(code || '').trim().toUpperCase();
  if (!code) throw new Error('গিফট কার্ড কোড লিখো।');
  const sh = getSheet_();
  const values = sh.getDataRange().getValues();
  for (let i=1; i<values.length; i++) {
    if (String(values[i][0]).toUpperCase() === code) {
      const expiry = values[i][3] instanceof Date ? values[i][3] : new Date(values[i][3]);
      const status = String(values[i][4] || '');
      const expired = isNaN(expiry.getTime()) || expiry.getTime() < Date.now();
      const effective = status === 'Used' ? 'Used' : (expired ? 'Expired' : 'Unused');
      return {found:true, code:code, discount:Number(values[i][1]), expiry:Utilities.formatDate(expiry, Session.getScriptTimeZone(), 'dd MMM yyyy'), status:effective};
    }
  }
  return {found:false};
}

function redeemGiftCard(token, code, customerName, mobile, orderNumber) {
  requireAdmin_(token);
  code = String(code || '').trim().toUpperCase();
  const sh = getSheet_();
  const lock = LockService.getScriptLock();
  lock.waitLock(10000);
  try {
    const values = sh.getDataRange().getValues();
    for (let i=1; i<values.length; i++) {
      if (String(values[i][0]).toUpperCase() === code) {
        const expiry = values[i][3] instanceof Date ? values[i][3] : new Date(values[i][3]);
        if (String(values[i][4]) === 'Used') throw new Error('এই গিফট কার্ডটি আগেই ব্যবহার করা হয়েছে।');
        if (isNaN(expiry.getTime()) || expiry.getTime() < Date.now()) {
          sh.getRange(i+1,5).setValue('Expired');
          throw new Error('এই গিফট কার্ডের মেয়াদ শেষ।');
        }
        sh.getRange(i+1,5,1,5).setValues([['Used', String(customerName||''), String(mobile||''), new Date(), String(orderNumber||'')]]);
        return {success:true, discount:Number(values[i][1])};
      }
    }
    throw new Error('কোডটি পাওয়া যায়নি।');
  } finally {
    lock.releaseLock();
  }
}

function listGiftCards(token) {
  requireAdmin_(token);
  const sh = getSheet_();
  const values = sh.getDataRange().getDisplayValues();
  return values.slice(1).reverse().slice(0,300).map(r => ({
    code:r[0], discount:r[1], issued:r[2], expiry:r[3], status:r[4],
    customer:r[5], mobile:r[6], redeemed:r[7], order:r[8]
  }));
}
