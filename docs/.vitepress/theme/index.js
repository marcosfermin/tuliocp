import Theme from 'vitepress/theme';
import '@fortawesome/fontawesome-free/css/fontawesome.css';
import '@fortawesome/fontawesome-free/css/solid.css';
import './styles/base.css';
import './styles/vars.css';
import 'floating-vue/dist/style.css';
import FloatingVue from 'floating-vue';
import InstallPage from './components/InstallPage.vue';

export default {
	...Theme,
	enhanceApp({ app }) {
		app.use(FloatingVue);
		app.component('InstallPage', InstallPage);
	},
};
