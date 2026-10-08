import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import vm from 'node:vm';
import '../customer-guide/config-engine.js';
import '../customer-guide/file-tools.js';
import '../customer-guide/server-guide.js';

const E=globalThis.BrandGuideEngine,F=globalThis.BrandGuideFiles,S=globalThis.CustomerServerGuide;
const source=readFileSync(new URL('../customer-guide/app.js',import.meta.url),'utf8');
const helpers=source.split('  // BEGIN BUNDLE IMPORT:')[1].split('\n').slice(1).join('\n').split('  // END BUNDLE IMPORT')[0];
const jsonImport=source.slice(source.indexOf('  function syncImportedConfig()'),source.indexOf('  // BEGIN BUNDLE IMPORT:'));
const sample=JSON.parse(readFileSync(new URL('../../mobile_flutter/config/sample.json',import.meta.url),'utf8'));
const png=new Uint8Array(readFileSync(new URL('../../mobile_flutter/config/assets/sample-icon.png',import.meta.url)));
const ttf=new Uint8Array(readFileSync(new URL('../../mobile_flutter/config/assets/hoppa-inter-400.ttf',import.meta.url)));

function fixture({firebase=true,fonts=true}={}) {
  const config=E.init(sample);
  Object.assign(config.app,{name:'Acme Pay',id:'acme',supportEmail:'support@acme.test',legalEntity:'Acme Ltd'});
  config.design.assets={logo:'assets/logo.png'};
  config.native.icon='assets/logo.png';
  config.native.androidApplicationId='com.acme.pay';config.native.iosBundleId='com.acme.pay';
  config.native.firebase=firebase?{android:'private/google-services.json',ios:'private/GoogleService-Info.plist'}:{};
  config.fonts=fonts?[{family:'Customer Sans',files:[{path:'assets/customer.ttf',weight:400,style:'normal'}]}]:[];
  config.design.typography.fontFamily=fonts?'Customer Sans':'Geist';
  config.flutterDefines.API_BASE_URL='https://api.acme.test';
  config.flutterDefines.PUBLIC_LABEL='Keep my advanced setting';
  const server={apiDomain:'api.acme.test',appDomain:'wallet.acme.test',adminDomain:'office.acme.test',dbMode:'managed',dbHost:'postgres.acme.test',dbPort:'5432',dbName:'acme_live',dbUser:'acme_runtime',dbSslMode:'VerifyFull',dbRootCert:'/etc/ssl/certs/acme-ca.pem',repoUrl:'git@github.com:acme/customer.git',brandId:config.app.id,appName:config.app.name,primaryColor:config.design.light.fill,supportEmail:config.app.supportEmail,legalEntity:config.app.legalEntity};
  const android={project_info:{project_id:'acme-project',project_number:'123456789'},client:[{client_info:{mobilesdk_app_id:'1:123456789:android:abc',android_client_info:{package_name:'com.acme.pay'}},api_key:[{current_key:'public-client-key'}]}]};
  const ios={PROJECT_ID:'acme-project',GCM_SENDER_ID:'123456789',GOOGLE_APP_ID:'1:123456789:ios:def',API_KEY:'public-client-key',BUNDLE_ID:'com.acme.pay'};
  const entries=[{name:'config/brand.json',bytes:JSON.stringify(config)},{name:'onboarding-settings.json',bytes:JSON.stringify(server)},{name:'config/assets/logo.png',bytes:png},{name:'config/assets/font-license.txt',bytes:'SIL Open Font License\n'},{name:'README.md',bytes:'Example handoff'},{name:'server-setup.md',bytes:'Example server guide'}];
  if(fonts)entries.push({name:'config/assets/customer.ttf',bytes:ttf});
  if(firebase)entries.push({name:'config/private/google-services.json',bytes:JSON.stringify(android)},{name:'config/private/GoogleService-Info.plist',bytes:'<plist><dict>'+Object.entries(ios).map(([key,value])=>`<key>${key}</key><string>${value}</string>`).join('')+'</dict></plist>'});
  return {config,server,entries,android,ios};
}

function harness({imageWidth=1024,fontFailure=false,fontRegistrationFailure=false}={}) {
  // Native browser decoders are represented by controlled doubles in these source-only tests.
  const faces=new Set(),calls={images:0,closed:0,loaded:0,render:0};
  class FixtureDOMParser {
    parseFromString(text){return {querySelector(selector){
      if(selector==='parsererror')return text.includes('<broken')?{}:null;
      if(selector==='plist > dict'&&text.includes('<dict>'))return {children:[...text.matchAll(/<(key|string|integer)>([^<]*)<\/\1>/g)].map(match=>({tagName:match[1],textContent:match[2]}))};
      return null;
    }};}
  }
  class PreviewFont {
    constructor(family,bytes,options){this.family=family;this.options=options;this.bytes=bytes;}
    async load(){calls.loaded++;if(fontFailure)throw new Error('Font decoding failed');return this;}
  }
  const context=vm.createContext({E,F,S,Map,Set,Uint8Array,TextEncoder,TextDecoder,Blob,URL,DOMParser:FixtureDOMParser,FontFace:PreviewFont,
    data:{assets:[{path:'assets/sample-icon.png',data:F.bytesToBase64(png),example:true}]},
    document:{fonts:{add(face){if(fontRegistrationFailure)throw new Error('Font registration failed');faces.add(face);},delete(face){faces.delete(face);}}},
    createImageBitmap:async()=>{calls.images++;return {width:imageWidth,height:1024,close(){calls.closed++;}};},
    render:()=>calls.render++,toast:()=>{},
  });
  vm.runInContext(`let lastImport='',config={app:{name:'Before import'}},server={apiDomain:'api.before.test',dbName:'old_db'},assets=new Map([['old.png',{data:'old'}]]);\n${jsonImport}\n${helpers}\nglobalThis.testApi={prepareImportedBundle,applyImportedBundle,applyImported,state:()=>({config,server,assets})};`,context);
  return {...context.testApi,calls,faces};
}

const mutateJson=(entries,name,change)=>entries.map(entry=>{if(entry.name!==name)return entry;const value=JSON.parse(entry.bytes);change(value);return {...entry,bytes:JSON.stringify(value)};});
const untouched=h=>{const state=h.state();assert.equal(state.config.app.name,'Before import');assert.equal(state.server.apiDomain,'api.before.test');assert.deepEqual([...state.assets.keys()],['old.png']);assert.equal(h.calls.render,0);assert.equal(h.faces.size,0);};

test('staged ZIP preparation restores complete assets and server choices without changing active state',async()=>{
  const input=fixture(),h=harness();
  const prepared=await h.prepareImportedBundle(F.makeZip(input.entries));
  untouched(h);
  assert.equal(prepared.config.flutterDefines.PUBLIC_LABEL,'Keep my advanced setting');
  assert.equal(prepared.server.dbMode,'managed');assert.equal(prepared.server.dbName,'acme_live');
  assert.equal(prepared.server.dbUser,'acme_runtime');assert.equal(prepared.server.dbRootCert,'/etc/ssl/certs/acme-ca.pem');
  assert.equal(prepared.assets.get('assets/logo.png').metadata.width,1024);
  assert.equal(prepared.assets.get('assets/logo.png').example,true,'Embedded sample artwork stays marked as an example even at a renamed path');
  assert.equal(prepared.assets.get('assets/customer.ttf').example,undefined);
  assert.equal(prepared.assets.get('assets/font-license.txt').license,true);
  assert.equal(prepared.assets.get('private/google-services.json').metadata.data.project_info.project_id,'acme-project');
  assert.equal(prepared.assets.get('private/GoogleService-Info.plist').metadata.data.BUNDLE_ID,'com.acme.pay');
  assert.deepEqual(F.base64ToBytes(prepared.assets.get('assets/customer.ttf').data),ttf);
  assert.equal(prepared.faces.length,1);assert.equal(h.calls.closed,1);
});

test('applying a valid handoff replaces config/assets and restores managed PostgreSQL settings together',async()=>{
  const input=fixture(),h=harness();
  await h.applyImportedBundle(F.makeZip(input.entries));
  const state=h.state();
  assert.equal(state.config.app.name,'Acme Pay');assert.equal(state.server.dbName,'acme_live');
  assert.equal(state.server.apiDomain,'api.acme.test');assert.equal(state.server.dbMode,'managed');
  assert.equal(state.assets.has('old.png'),false);assert.equal(state.assets.size,5);
  assert.equal(h.faces.size,1);assert.equal(h.calls.render,1);
  assert.equal(E.validateConfig(state.config,new Map([...state.assets].map(([path,item])=>[path,item.metadata]))).valid,true);
});

test('invalid config, missing assets, server secrets, and inconsistent public settings leave current work intact',async()=>{
  const input=fixture();
  const cases=[
    [input.entries.filter(entry=>entry.name!=='config/assets/logo.png'),/missing its referenced file/],
    [input.entries.filter(entry=>entry.name!=='onboarding-settings.json'),/original handoff ZIP/],
    [mutateJson(input.entries,'config/brand.json',value=>value.schemaVersion=99),/schemaVersion/],
    [mutateJson(input.entries,'config/brand.json',value=>value.flutterDefines.DATABASE_PASSWORD='private'),/Server credentials/],
    [mutateJson(input.entries,'onboarding-settings.json',value=>value.password='private'),/Only public fields/],
    [mutateJson(input.entries,'onboarding-settings.json',value=>value.apiDomain='wrong.acme.test'),/API URL/],
    [mutateJson(input.entries,'onboarding-settings.json',value=>value.brandId='another'),/does not match/],
    [mutateJson(input.entries,'onboarding-settings.json',value=>value.dbSslMode='Disable'),/VerifyFull/],
    [mutateJson(input.entries,'onboarding-settings.json',value=>value.repoUrl='https://token@github.com/acme/repo'),/repository URL/],
    [[...input.entries,{name:'config/private/service-account.json',bytes:'{}'}],/Unexpected or oversized asset/],
  ];
  for(const [entries,pattern] of cases){const h=harness();await assert.rejects(h.applyImportedBundle(F.makeZip(entries)),pattern);untouched(h);}
});

test('images, fonts, and Firebase metadata are validated before committing imported state',async()=>{
  const input=fixture();
  const badAndroid=mutateJson(input.entries,'config/private/google-services.json',value=>value.client[0].client_info.android_client_info.package_name='com.wrong.app');
  const serverKey=mutateJson(input.entries,'config/private/google-services.json',value=>value.private_key='do not include me');
  const cases=[
    [harness({imageWidth:8193}),input.entries,/8192 pixels/],
    [harness({fontFailure:true}),input.entries,/Font decoding failed/],
    [harness({fontRegistrationFailure:true}),input.entries,/Font registration failed/],
    [harness(),badAndroid,/Android application ID/],
    [harness(),serverKey,/Server credentials/],
    [harness(),input.entries.map(entry=>entry.name==='config/assets/logo.png'?{...entry,bytes:'not an image'}:entry),/Image contents/],
    [harness(),input.entries.map(entry=>entry.name.endsWith('.plist')?{...entry,bytes:'<broken'}:entry),/valid XML/],
  ];
  for(const [h,entries,pattern] of cases){await assert.rejects(h.applyImportedBundle(F.makeZip(entries)),pattern);untouched(h);}
});

test('JSON-only import keeps its established behavior and does not pretend to restore asset bytes or server choices',()=>{
  const input=fixture(),h=harness();
  const report=h.applyImported(input.config);
  assert.equal(report.valid,true);assert.equal(h.state().config.app.name,'Acme Pay');
  assert.equal(h.state().server.dbName,'acme');assert.equal(h.state().server.apiDomain,'api.acme.test');
  assert.deepEqual([...h.state().assets.keys()],['old.png']);assert.equal(h.faces.size,0);
  assert.equal(h.state().config.flutterDefines.PUBLIC_LABEL,'Keep my advanced setting');
});

test('an in-flight ZIP import cannot replace a later valid JSON import',async()=>{
  const input=fixture(),h=harness();
  const pending=h.applyImportedBundle(F.makeZip(input.entries));
  const newer=E.clone(input.config);newer.app.name='Most recent import';
  h.applyImported(newer);
  await pending;
  assert.equal(h.state().config.app.name,'Most recent import');assert.equal(h.faces.size,0);
  assert.deepEqual([...h.state().assets.keys()],['old.png']);
});
